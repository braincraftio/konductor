---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:dev,k9:ci:dev:qcow2
runme:
  version: v3
---

# Developer Tools

Human-in-the-loop development workflow tools. Not called by `ci:pipeline`.

## Contents

- [dev:clean](#devclean) — Reset build state
- [dev:start](#devstart) — Boot VM for development
- [dev:ssh](#devssh) — SSH into running VM
- [dev:stop](#devstop) — Shutdown VM
- [dev:rebase](#devrebase) — Rebuild NixOS host from flake
- [dev:vendor](#devvendor) — Vendor flake inputs offline
- [dev:vendor:online](#devvendoronline) — Online refresh + vendor
- [dev:log](#devlog) — View serial console log
- [dev:kill](#devkill) — Force kill QEMU

---

## dev:clean

Reset build state.

```bash {"name":"k9:ci:dev:clean","excludeFromRunAll":"true","tag":"k9:ci:dev,type:destructive"}
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo umount -f "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
fusermount -uz "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
sudo rm -rf "${QCOW2_MOUNT:-/tmp/nixmount}" "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
sudo rm -rf result result.writable konductor.qcow2 konductor.qcow2.tmp .konductor .nix_drv .system-toplevel
echo "✓ Clean"
```

---

## dev:start

Boot VM for local development and testing.

**What it does:**

1. Cleans any existing VM runtime state
2. Generates cloud-init ISO (via build.md `_build:cloudinit`)
3. Boots QCOW2 image with QEMU (via build.md `_build:vm:boot`)
4. Waits for SSH to be available (via build.md `_build:vm:wait`)

**Port forwarding:**

- SSH: localhost:2222 → VM:22 (configurable via `QCOW2_SSH_PORT`)
- VS Code: localhost:18080 → VM:8080 (configurable via `QCOW2_VSCODE_PORT`)
- TTYD: localhost:17681 → VM:7681 (configurable via `QCOW2_TTYD_PORT`)

**Prerequisites:** `result/nixos.qcow2` exists (run `build:image` first)

```bash {"name":"k9:ci:dev:start","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry,requires:kvm"}
set -e
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. Use: ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
    exit 0
fi

# Prefer final compressed image, fall back to build overlay
if [ -f konductor.qcow2 ]; then
    BACKING="$(readlink -f konductor.qcow2)"
elif [ -f result/nixos.qcow2 ]; then
    BACKING="$(readlink -f result/nixos.qcow2)"
else
    echo "No image. Run build:all or build:image first."
    exit 1
fi

# Clean VM runtime state only — kill by PID file, not by pattern match
# (pkill -f can match the script's own process and self-kill)
if [ -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" ]; then
    kill -9 "$(cat "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}")" 2>/dev/null || true
fi
rm -f "$PIDFILE" "${QCOW2_LOGFILE:-build-vm.log}"
sudo rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

# Create writable overlay for dev use (preserves original image)
rm -rf result.dev && mkdir -p result.dev
qemu-img create -f qcow2 -b "$BACKING" -F qcow2 result.dev/nixos.qcow2
rm -f result && ln -sf result.dev result

# Generate cloud-init ISO (reuse build block)
runme run k9:ci:qcow2:build:_cloudinit

# Ports
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
VSCODE_PORT="${QCOW2_VSCODE_PORT:-18080}"
TTYD_PORT="${QCOW2_TTYD_PORT:-17681}"
CLOUD_INIT_DIR="${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

# Calculate CPUs: all cores minus 2, minimum 2
TOTAL_CPUS=$(nproc)
VM_CPUS=$((TOTAL_CPUS - 2))
[ "$VM_CPUS" -lt 2 ] && VM_CPUS=2

echo "Booting sealed image standalone (no virtiofs, no host mounts)"
echo "  Image: $BACKING"
echo "  CPUs: $VM_CPUS / $TOTAL_CPUS"

# Standalone QEMU — no virtiofs, no 9p, no host dependencies.
# The sealed konductor.qcow2 has a complete self-contained nix store.
# This proves the image can boot on any hypervisor, KubeVirt, or bare metal.
VM_MEMORY="${QCOW2_VM_MEMORY:-16384}"
qemu-system-x86_64 \
    -machine q35,accel=kvm,mem-merge=on \
    -m "$VM_MEMORY" \
    -cpu host \
    -smp "${QCOW2_VM_CPUS:-$VM_CPUS}" \
    -rtc base=utc,clock=host \
    -boot order=c,menu=off \
    -object iothread,id=iot0 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$CLOUD_INIT_DIR/OVMF_VARS.fd" \
    -drive file=result/nixos.qcow2,if=none,id=drive0,format=qcow2,cache=writeback,aio=io_uring,discard=unmap,detect-zeroes=unmap \
    -device virtio-blk-pci,drive=drive0,iothread=iot0,num-queues=4 \
    -drive file="$CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,restrict=off,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${VSCODE_PORT}-:8080,hostfwd=tcp::${TTYD_PORT}-:7681 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -daemonize \
    -pidfile "$PIDFILE" \
    -serial file:"${QCOW2_LOGFILE:-build-vm.log}" \
    -display none

sleep 1
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
    || { echo "QEMU failed to start"; tail -20 "${QCOW2_LOGFILE:-build-vm.log}"; exit 1; }

echo "VM started: SSH=$SSH_PORT, VSCode=$VSCODE_PORT, TTYD=$TTYD_PORT"

# Wait for SSH
runme run k9:ci:qcow2:build:_vm-wait

echo "VM ready:"
echo "  SSH:     ssh -p $SSH_PORT kc2admin@localhost"
echo "  VS Code: http://localhost:$VSCODE_PORT"
echo "  TTYD:    http://localhost:$TTYD_PORT"
```

---

## dev:ssh

SSH into running VM.

**Default port:** 2222 (configurable via `QCOW2_SSH_PORT`)

```bash {"name":"k9:ci:dev:ssh","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry,interactive:true"}
ssh -p "${QCOW2_SSH_PORT:-2222}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null kc2admin@localhost
```

---

## dev:stop

Gracefully shutdown running VM.

```bash {"name":"k9:ci:dev:stop","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry"}
runme run k9:ci:qcow2:build:_vm-halt
```

---

## dev:rebase

Rebuild NixOS host from flake (dogfooding).

**Use case:** Testing flake changes on the build host itself.

**Warning:** This rebuilds the NixOS system running the build. Only use on NixOS hosts.

```bash {"name":"k9:ci:dev:rebase","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry,requires:nixos"}
set -e

# Generate --override-input flags from vendored sources for offline rebuild.
# Prefers baked-in /etc/konductor/input-sources.env (exact store paths from
# image build), falls back to _sources/ directory from dev:vendor.
OVERRIDE_INPUTS=""
if [ -f /etc/konductor/input-sources.env ]; then
    echo "Using baked-in input sources from /etc/konductor/input-sources.env..."
    while IFS="=" read -r name spath; do
        [ -n "$name" ] && [ -n "$spath" ] && OVERRIDE_INPUTS="$OVERRIDE_INPUTS --override-input $name path:$spath"
    done < /etc/konductor/input-sources.env
elif [ -f _sources/manifest.txt ]; then
    echo "Using vendored sources from _sources/manifest.txt..."
    while read -r name spath; do
        [ -n "$name" ] && [ -n "$spath" ] && OVERRIDE_INPUTS="$OVERRIDE_INPUTS --override-input $name path:$spath"
    done < _sources/manifest.txt
else
    echo "⚠ No vendored sources found, fetching from network..."
fi

sudo -E nixos-rebuild switch --flake '.#konductor' --no-write-lock-file $OVERRIDE_INPUTS
echo "✓ NixOS rebuilt. Run 'direnv reload' to pick up environment changes."
```

---

## dev:vendor

Vendor all flake inputs into `./_sources` for fully offline builds.

```bash {"name":"k9:ci:dev:vendor","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry"}
set -euo pipefail

# Unset GITHUB_TOKEN to prevent nix from authenticating to api.github.com
# with the Forgejo job token (which GitHub rejects as "Bad credentials").
# Public repos fetch fine without auth; the Forgejo token is not valid on GitHub.
unset GITHUB_TOKEN

echo "Vendoring flake inputs into ./_sources ..."
sudo -E rm -rf _sources
mkdir -p _sources
sudo -E chown -R "$(id -u):$(id -g)" _sources

export XDG_CACHE_HOME="/tmp/konductor-nix-cache"
export HOME="/tmp/konductor-nix-home"
mkdir -p "$XDG_CACHE_HOME" "$HOME"

# Read from committed flake.lock (has github refs), not working copy (may have path refs)
# This ensures we always have fetchable URLs even after nixos-rebuild modifies the working copy
git show HEAD:flake.lock > /tmp/flake.lock.reference

jq -c '
  .nodes as $nodes
  | (.nodes.root.inputs | keys) as $roots
  | ($roots + ["flake-parts","nuschtosSearch","ixx","nixlib","systems"])
  | unique
  | map(select($nodes[.] != null))
  | .[]
  | . as $k
  | {name:$k} + ($nodes[$k])
  | [
      .name,
      .locked.type,
      (.locked.owner // null),
      (.locked.repo // null),
      (.locked.rev // null),
      (.locked.ref // null),
      (.locked.url // null)
    ]
' /tmp/flake.lock.reference > /tmp/vendor-lock.jsonl
rm -f /tmp/flake.lock.reference

while read -r row; do
  name=$(jq -r '.[0]' <<<"$row")
  typ=$(jq -r '.[1]' <<<"$row")
  owner=$(jq -r '.[2] // empty' <<<"$row")
  repo=$(jq -r '.[3] // empty' <<<"$row")
  rev=$(jq -r '.[4] // empty' <<<"$row")
  ref=$(jq -r '.[5] // empty' <<<"$row")
  url=$(jq -r '.[6] // empty' <<<"$row")
  [ -n "$name" ] || continue
  case "$typ" in
    github)
      flakeref="github:${owner}/${repo}/${rev}"
      ;;
    git)
      flakeref="git+${url}?rev=${rev}"
      ;;
    *)
      echo "Skipping unsupported input type: $name ($typ)"
      continue
      ;;
  esac
  echo "  -> $name"
  attempt=1
  max_attempts=3
  while :; do
    if XDG_CACHE_HOME="$XDG_CACHE_HOME" HOME="$HOME" \
      nix --extra-experimental-features 'nix-command flakes' \
      flake prefetch --no-use-registries --refresh --json "$flakeref" > /tmp/prefetch.json 2>/tmp/prefetch.err; then
      break
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Error: prefetch failed for $name ($flakeref)"
      echo "--- stderr ---"
      cat /tmp/prefetch.err || true
      echo "--- stdout ---"
      cat /tmp/prefetch.json || true
      exit 1
    fi
    echo "  retry ${attempt}/${max_attempts} for $name (clearing tarball cache)"
    rm -rf "$XDG_CACHE_HOME/nix/tarball-cache" "$XDG_CACHE_HOME/nix/tarball-cache-"* || true
    attempt=$((attempt + 1))
  done
  if ! store_path=$(jq -e -r '.storePath' /tmp/prefetch.json); then
    echo "Error: failed to resolve store path for $name ($flakeref)"
    cat /tmp/prefetch.json
    rm -f /tmp/prefetch.json
    exit 1
  fi
  if [[ "$store_path" != /nix/store/* ]]; then
    echo "Error: invalid store path for $name ($flakeref): $store_path"
    cat /tmp/prefetch.json
    rm -f /tmp/prefetch.json
    exit 1
  fi
  rm -f /tmp/prefetch.json

  # Record store path for this input (used by --override-input in VM builds).
  # Also rsync a working copy for tools that need a writable tree.
  echo "$name $store_path" >> _sources/manifest.txt
  rsync -a --chmod=Du+w,Fu+w "$store_path/" "_sources/$name/"
done < /tmp/vendor-lock.jsonl

rm -f /tmp/vendor-lock.jsonl
unset XDG_CACHE_HOME HOME

# NOTE: We do NOT run 'nix flake lock' here.
# The committed flake.lock has github refs; keep it that way for future vendor runs.
# The VM build uses store paths from manifest.txt for --override-input flags,
# which preserves exact narHashes and matches the host's derivation hashes.

echo "✓ Vendored inputs into ./_sources"
echo "  Manifest:"
cat _sources/manifest.txt
ls _sources/
```

---

## dev:vendor:online

Intermittent online refresh: update lock from network, then vendor into `./_sources`, then re-lock
to local paths for offline builds.

```bash {"name":"k9:ci:dev:vendor-online","excludeFromRunAll":"true","tag":"k9:ci:dev,type:entry"}
set -euo pipefail

# Unset GITHUB_TOKEN to prevent nix from sending the Forgejo job token to GitHub API.
unset GITHUB_TOKEN

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Refreshing flake.lock from network (temp flake in $tmpdir)..."

cat > "$tmpdir/flake.nix" <<'EOF'
{
  description = "Konductor lock refresh (network)";
  inputs = {
EOF

# Read from committed flake.lock (has github refs), not working copy
git show HEAD:flake.lock > "$tmpdir/flake.lock.reference"

# Build input list from committed lock (prefer original refs, fallback to locked).
jq -c '
  .nodes as $nodes
  | (.nodes.root.inputs | keys) as $roots
  | ($roots + ["flake-parts","nuschtosSearch","ixx","nixlib","systems"])
  | unique
  | map(select($nodes[.] != null))
  | .[]
  | . as $k
  | {name:$k, locked:($nodes[$k].locked // {}), original:($nodes[$k].original // {}), flake:($nodes[$k].flake // true)}
  | [
      .name,
      (.original.type // .locked.type // null),
      (.original.owner // .locked.owner // null),
      (.original.repo // .locked.repo // null),
      (.original.ref // .locked.ref // null),
      (.original.rev // .locked.rev // null),
      (.original.url // .locked.url // null),
      (.original.dir // .locked.dir // null),
      (if .flake == false then "false" else "true" end)
    ]
' "$tmpdir/flake.lock.reference" > "$tmpdir/inputs.jsonl"

while read -r row; do
  name=$(jq -r '.[0]' <<<"$row")
  typ=$(jq -r '.[1] // empty' <<<"$row")
  owner=$(jq -r '.[2] // empty' <<<"$row")
  repo=$(jq -r '.[3] // empty' <<<"$row")
  ref=$(jq -r '.[4] // empty' <<<"$row")
  rev=$(jq -r '.[5] // empty' <<<"$row")
  url=$(jq -r '.[6] // empty' <<<"$row")
  dir=$(jq -r '.[7] // empty' <<<"$row")
  is_flake=$(jq -r '.[8] // "true"' <<<"$row")
  [ -n "$name" ] || continue
  case "$typ" in
    github)
      if [ -n "$ref" ] && [ "$ref" != "null" ]; then
        flakeref="github:${owner}/${repo}/${ref}"
      elif [ -n "$rev" ] && [ "$rev" != "null" ]; then
        flakeref="github:${owner}/${repo}/${rev}"
      else
        flakeref="github:${owner}/${repo}"
      fi
      ;;
    git)
      if [ -n "$ref" ] && [ "$ref" != "null" ]; then
        flakeref="git+${url}?ref=${ref}"
      elif [ -n "$rev" ] && [ "$rev" != "null" ]; then
        flakeref="git+${url}?rev=${rev}"
      else
        flakeref="git+${url}"
      fi
      ;;
    *)
      echo "Skipping unsupported input type: $name ($typ)"
      continue
      ;;
  esac
  if [ -n "$dir" ] && [ "$dir" != "null" ]; then
    if [[ "$flakeref" == *"?"* ]]; then
      flakeref="${flakeref}&dir=${dir}"
    else
      flakeref="${flakeref}?dir=${dir}"
    fi
  fi
  echo "    ${name}.url = \"${flakeref}\";" >> "$tmpdir/flake.nix"
  if [ "$is_flake" = "false" ]; then
    echo "    ${name}.flake = false;" >> "$tmpdir/flake.nix"
  fi
done < "$tmpdir/inputs.jsonl"

cat >> "$tmpdir/flake.nix" <<'EOF'
  };
  outputs = { self, ... }: { };
}
EOF

nix --extra-experimental-features 'nix-command flakes' flake update --flake "$tmpdir"
cp -f "$tmpdir/flake.lock" ./flake.lock

echo "Vendoring refreshed inputs into ./_sources ..."
runme run k9:ci:dev:vendor

echo "✓ Online refresh complete: flake.lock + _sources updated for offline use"
```

---

## dev:log

View boot log.

```bash {"name":"k9:ci:dev:log","excludeFromRunAll":"true","tag":"k9:ci:dev,type:debug"}
bat "${QCOW2_LOGFILE:-build-vm.log}"
```

---

## dev:kill

Force kill VM.

```bash {"name":"k9:ci:dev:kill","excludeFromRunAll":"true","tag":"k9:ci:dev,type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
```
