---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: scope:dev,target:qcow2
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

```bash {"name":"dev:clean","excludeFromRunAll":"true","tag":"type:destructive"}
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

```sh {"name":"dev:start","excludeFromRunAll":"true","tag":"type:entry,scope:dev,requires:kvm"}
set -e
BUILD_FILE="docs/ci/build.md"
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

# Clean VM runtime state only
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

# Create writable overlay for dev use (preserves original image)
rm -rf result.dev && mkdir -p result.dev
qemu-img create -f qcow2 -b "$BACKING" -F qcow2 result.dev/nixos.qcow2
rm -f result && ln -sf result.dev result

runme run --direnv=true --load-env=false --filename "$BUILD_FILE" _build:cloudinit
runme run --direnv=true --load-env=false --filename "$BUILD_FILE" _build:vm:boot
runme run --direnv=true --load-env=false --filename "$BUILD_FILE" _build:vm:wait

echo "VM ready:"
echo "  SSH:     ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
echo "  VS Code: http://localhost:${QCOW2_VSCODE_PORT:-18080}"
echo "  TTYD:    http://localhost:${QCOW2_TTYD_PORT:-17681}"
```

---

## dev:ssh

SSH into running VM.

**Default port:** 2222 (configurable via `QCOW2_SSH_PORT`)

```sh {"name":"dev:ssh","excludeFromRunAll":"true","tag":"type:entry,scope:dev,interactive:true"}
ssh -p "${QCOW2_SSH_PORT:-2222}" kc2admin@localhost
```

---

## dev:stop

Gracefully shutdown running VM.

```sh {"name":"dev:stop","excludeFromRunAll":"true","tag":"type:entry,scope:dev"}
BUILD_FILE="docs/ci/build.md"
runme run --direnv=true --load-env=false --filename "$BUILD_FILE" _build:vm:halt
```

---

## dev:rebase

Rebuild NixOS host from flake (dogfooding).

**Use case:** Testing flake changes on the build host itself.

**Warning:** This rebuilds the NixOS system running the build. Only use on NixOS hosts.

```sh {"name":"dev:rebase","excludeFromRunAll":"true","tag":"type:entry,scope:dev,requires:nixos"}
set -e
sudo nixos-rebuild switch --flake .#konductor
echo "✓ NixOS rebuilt. Run 'direnv reload' to pick up environment changes."
```

---

## dev:vendor

Vendor all flake inputs into `./_sources` for fully offline builds.

```bash {"name":"dev:vendor","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail

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
      flake prefetch --no-use-registries --refresh --json "$flakeref" > /tmp/prefetch.json 2>/dev/null; then
      break
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Error: prefetch failed for $name ($flakeref)"
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

```bash {"name":"dev:vendor:online","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail

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
runme run --filename docs/ci/dev.md dev:vendor

echo "✓ Online refresh complete: flake.lock + _sources updated for offline use"
```

---

## dev:log

View boot log.

```bash {"name":"dev:log","excludeFromRunAll":"true","tag":"type:debug"}
bat "${QCOW2_LOGFILE:-build-vm.log}"
```

---

## dev:kill

Force kill VM.

```bash {"name":"dev:kill","excludeFromRunAll":"true","tag":"type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
```
