---
cwd: ../../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: target:qcow2,scope:standalone
runme:
  version: v3
  debug: true
---

# Konductor QCOW2 OCI Build (Standalone)

Standalone offline build pipeline for QCOW2 VM image with OCI containerDisk packaging.

This file is self-contained and does not require the parent workspace or mise tasks.
It can be used directly from `/opt/konductor/src` without external dependencies.

## Contents

- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [Task Reference](#task-reference)
- [Pipeline Tasks](#pipeline-tasks)

---

## Quick Start

```bash
# Full build pipeline (clean → nix → vm → seal → container)
runme run oci:build

# Push to registry
runme run oci:push

# Or run individual steps
runme run oci:clean
runme run oci:image
runme run oci:container
```

---

## Environment Variables

Set these in `.env` or export before running:

```bash
# Registry configuration
export OCI_REGISTRY="registry.ucs.arpa"
export OCI_IMAGE="helix/flake"
export OCI_TAG="latest-qcow2"

# Optional: Skip phases for iteration
export SKIP_NIX_BUILD=false
export SKIP_VM_PHASE=false
export SKIP_COMPRESS=false
```

---

## Task Reference

```text
Entry Points:
  oci:build              Full pipeline: clean → image → container
  oci:image              Build QCOW2 only
  oci:container          Package QCOW2 as containerDisk
  oci:push               Push to registry
  oci:clean              Reset build state

Development:
  oci:start              Boot VM for development
  oci:ssh                SSH into running VM
  oci:stop               Shutdown VM
  oci:vendor:inputs           Vendor flake inputs into ./_sources (online)
  oci:vendor:inputs:online    Refresh lock + vendor inputs from network (intermittent)

Debug:
  oci:debug:log          View boot log
  oci:vm:kill            Force kill VM
```

---

## oci:build

Full pipeline: clean → image → container.

```sh {"name":"oci:build","excludeFromRunAll":"true","tag":"type:entry"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  oci:build - Standalone QCOW2 + OCI Build Pipeline"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Target: ${OCI_REGISTRY:-registry.ucs.arpa}/${OCI_IMAGE:-helix/flake}:${OCI_TAG:-latest-qcow2}"
echo ""

OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"

echo "▶ Phase 1: Clean..."
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" oci:clean

echo ""
echo "▶ Phase 2: Build QCOW2 image..."
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" oci:image

echo ""
echo "▶ Phase 3: Package as containerDisk..."
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" oci:container

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ Build complete!"
echo "═══════════════════════════════════════════════════════════════════════════"
cat .konductor
```

---

## oci:image

Build QCOW2: nix → VM configure → seal → verify.

```sh {"name":"oci:image","excludeFromRunAll":"true","tag":"type:entry"}
set -e
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"

# Pipeline phases in order
PHASES=(
    "_oci:preflight"
    "_oci:nix"
    "_oci:cloudinit"
    "_oci:img:reset"
    "_oci:vm:boot"
    "_oci:vm:wait"
    "_oci:vm:sync"
    "_oci:vm:rebuild"
    "_oci:vm:pki:test"
    "_oci:vm:pki:status"
    "_oci:vm:provenance"
    "_oci:vm:gc"
    "_oci:vm:zero"
    "_oci:vm:halt"
    "_oci:img:clean"
    "_oci:img:compress"
    "_oci:img:sparsify"
    "_oci:tmp:clean"
    "_oci:verify"
)

for phase in "${PHASES[@]}"; do
    echo ""
    echo "▶ ${phase}..."
    runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" "$phase"
done
```

---

## oci:container

Package QCOW2 as containerDisk.

```sh {"name":"oci:container","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
REGISTRY="${OCI_REGISTRY:-registry.ucs.arpa}"
IMAGE="${OCI_IMAGE:-helix/flake}"
TAG="${OCI_TAG:-latest-qcow2}"
FULL_IMAGE="${REGISTRY}/${IMAGE}:${TAG}"

[ -f konductor.qcow2 ] || { echo "Error: konductor.qcow2 not found"; exit 1; }
[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }
[ -f Dockerfile.qcow2 ] || { echo "Error: Dockerfile.qcow2 not found"; exit 1; }
[ -f "${QCOW2_LOGFILE:-build-vm.log}" ] || echo "# VM phase skipped" > "${QCOW2_LOGFILE:-build-vm.log}"

docker buildx build -f Dockerfile.qcow2 \
    --build-arg QCOW2_FILE=konductor.qcow2 \
    --build-arg BUILD_LOG="${QCOW2_LOGFILE:-build-vm.log}" \
    --build-arg PROVENANCE=.konductor \
    --provenance=false --sbom=false \
    --load -t "$FULL_IMAGE" .

echo "✓ Built: $FULL_IMAGE"
```

---

## oci:push

Push container with multi-tag (git/nix/latest).

```sh {"name":"oci:push","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
REGISTRY="${OCI_REGISTRY:-registry.ucs.arpa}"
IMAGE="${OCI_IMAGE:-helix/flake}"
BASE_TAG="${OCI_TAG:-latest-qcow2}"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

# Build tag list
TAGS=("$BASE_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("qcow2-${git_commit:0:12}")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("qcow2-${nix_drv:0:12}")
fi

FULL_IMAGE="$REGISTRY/$IMAGE:$BASE_TAG"
docker image inspect "$FULL_IMAGE" &>/dev/null || { echo "Error: $FULL_IMAGE not found locally"; exit 1; }

# Push with all tags
for tag in "${TAGS[@]}"; do
    echo "Pushing ${REGISTRY}/${IMAGE}:${tag}..."
    docker tag "$FULL_IMAGE" "$REGISTRY/$IMAGE:$tag"
    docker push "$REGISTRY/$IMAGE:$tag"
done

echo ""
echo "Pushed: $REGISTRY/$IMAGE"
printf "  %s\n" "${TAGS[@]}"
```

---

## oci:clean

Reset build state.

```sh {"name":"oci:clean","excludeFromRunAll":"true","tag":"type:destructive"}
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo umount -f "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
fusermount -uz "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
sudo rm -rf "${QCOW2_MOUNT:-/tmp/nixmount}" "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -rf result result.writable konductor.qcow2 konductor.qcow2.tmp .konductor .nix_drv
echo "✓ Clean"
```

---

## oci:start

Boot image for local development.

```sh {"name":"oci:start","excludeFromRunAll":"true","tag":"type:entry"}
set -e
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. Use: ssh kc2@localhost"
    exit 0
fi
[ -f result/nixos.qcow2 ] || { echo "No image. Run oci:image first."; exit 1; }

# Clean VM runtime state only (not the image)
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" _oci:cloudinit
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:boot
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:wait
echo "VM ready: ssh kc2@localhost"
```

---

## oci:ssh

```sh {"name":"oci:ssh","excludeFromRunAll":"true","tag":"type:entry"}
ssh kc2@localhost
```

---

## oci:stop

```sh {"name":"oci:stop","excludeFromRunAll":"true","tag":"type:entry"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=false --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:halt
```

---

## oci:vendor:inputs

Vendor all flake inputs into `./_sources` for fully offline builds.

```sh {"name":"oci:vendor:inputs","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail

echo "Vendoring flake inputs into ./_sources ..."
sudo -E rm -rf _sources
mkdir -p _sources
sudo -E chown -R "$(id -u):$(id -g)" _sources

export XDG_CACHE_HOME="/tmp/konductor-nix-cache"
export HOME="/tmp/konductor-nix-home"
mkdir -p "$XDG_CACHE_HOME" "$HOME"

# Resolve inputs from flake.lock (works even when flake.nix uses path inputs).
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
' flake.lock > /tmp/vendor-lock.jsonl

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
    XDG_CACHE_HOME="$XDG_CACHE_HOME" HOME="$HOME" \
      nix --extra-experimental-features 'nix-command flakes' \
      flake prefetch --no-use-registries --refresh --json "$flakeref" > /tmp/prefetch.json 2>/dev/null && break
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Error: prefetch failed for $name ($flakeref)"
      cat /tmp/prefetch.json 2>/dev/null || true
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
  rsync -a --chmod=Du+w,Fu+w "$store_path/" "_sources/$name/"
done < /tmp/vendor-lock.jsonl

rm -f /tmp/vendor-lock.jsonl
unset XDG_CACHE_HOME HOME

# Refresh flake.lock now that inputs are local paths.
nix --extra-experimental-features 'nix-command flakes' flake lock

echo "✓ Vendored inputs into ./_sources"
```

---

## oci:vendor:inputs:online

Intermittent online refresh: update lock from network, then vendor into `./_sources`,
then re-lock to local paths for offline builds.

```sh {"name":"oci:vendor:inputs:online","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Refreshing flake.lock from network (temp flake in $tmpdir)..."

cat > "$tmpdir/flake.nix" <<'EOF'
{
  description = "Konductor lock refresh (network)";
  inputs = {
EOF

# Build input list from existing lock (prefer original refs, fallback to locked).
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
' flake.lock > "$tmpdir/inputs.jsonl"

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
runme run oci:vendor:inputs

echo "✓ Online refresh complete: flake.lock + _sources updated for offline use"
```

---

---

## Pipeline Tasks

### \_oci:preflight

Validate environment (standalone - no cluster required).

```sh {"name":"_oci:preflight"}
set -e

# Build host system state
ff 2>/dev/null || fastfetch 2>/dev/null || echo "(fastfetch not available)"

# Resolve WORKSPACE_ROOT: env > PWD
export WORKSPACE_ROOT="${WORKSPACE_ROOT:-$PWD}"
[[ "${WORKSPACE_ROOT}" == /* ]] && printf "✓ WORKSPACE_ROOT=%s\n" "$WORKSPACE_ROOT" || { echo "✗ WORKSPACE_ROOT='${WORKSPACE_ROOT}' must be absolute"; exit 1; }

ERRORS=0

# ─────────────────────────────────────────────────────────────────────
# VALIDATE CLEAN STATE
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Clean state validation:"

[ ! -e result ] && printf "✓ no result/\n" || { printf "✗ stale result/ exists (run oci:clean)\n"; ((ERRORS++)); }
[ ! -e result.writable ] && printf "✓ no result.writable/\n" || { printf "✗ stale result.writable/ exists\n"; ((ERRORS++)); }
[ ! -e konductor.qcow2 ] && printf "✓ no konductor.qcow2\n" || { printf "✗ stale konductor.qcow2 exists\n"; ((ERRORS++)); }
[ ! -e .konductor ] && printf "✓ no .konductor\n" || { printf "✗ stale .konductor exists\n"; ((ERRORS++)); }

# ─────────────────────────────────────────────────────────────────────
# REQUIRED BINARIES
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Environment validation:"

REQUIRED_BINS="${QCOW2_REQUIRED_BINS:-nix qemu-img qemu-system-x86_64 genisoimage guestmount guestunmount virt-sparsify ssh rsync timeout ss du sha256sum jq docker}"

for cmd in $REQUIRED_BINS; do
    if command -v "$cmd" &>/dev/null; then
        path=$(command -v "$cmd")
        printf "✓ %-20s %s\n" "$cmd" "$path"
    else
        printf "✗ %s\n" "$cmd"
        ((ERRORS++))
    fi
done

# Print versions for critical tools
echo ""
echo "Versions:"
printf "  qemu:   %s\n" "$(qemu-system-x86_64 --version | head -1)"
printf "  nix:    %s\n" "$(nix --version)"
printf "  docker: %s\n" "$(docker --version)"

# ─────────────────────────────────────────────────────────────────────
# FLAKE ATTESTATION (informational - network errors are non-fatal)
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Flake metadata:"
if nix flake metadata . --no-write-lock-file --json 2>/dev/null | jq '{
  path,
  lastModified: .lastModified,
  narHash: .locked.narHash // "unlocked",
  inputs: (.locks.nodes | to_entries | map(select(.key != "root")) | map({
    (.key): {
      type: .value.locked.type,
      rev: (.value.locked.rev // "n/a"),
      narHash: (.value.locked.narHash // "n/a")
    }
  }) | add // {})
}' 2>/dev/null; then
    :
else
    echo "  (skipped - network/SSL error, using cached inputs)"
fi

echo ""
echo "Flake outputs:"
if ! nix flake show . --json 2>/dev/null | jq 'keys' 2>/dev/null; then
    echo "  (skipped - network/SSL error)"
fi

# ─────────────────────────────────────────────────────────────────────
# OVMF FIRMWARE
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "OVMF firmware:"
[ -n "$OVMF_CODE" ] && [ -f "$OVMF_CODE" ] && printf "✓ OVMF_CODE=%s\n" "$OVMF_CODE" || { printf "✗ OVMF_CODE not set or missing\n"; ((ERRORS++)); }
[ -n "$OVMF_VARS" ] && [ -f "$OVMF_VARS" ] && printf "✓ OVMF_VARS=%s\n" "$OVMF_VARS" || { printf "✗ OVMF_VARS not set or missing\n"; ((ERRORS++)); }

# ─────────────────────────────────────────────────────────────────────
# SSH KEY
# ─────────────────────────────────────────────────────────────────────
SSH_PUBKEY="${QCOW2_SSH_KEY_DIR:-$HOME/.ssh}/id_ed25519.pub"
ssh-keygen -l -f "$SSH_PUBKEY" &>/dev/null && printf "✓ SSH key: %s\n" "$SSH_PUBKEY" || { printf "✗ SSH key: %s\n" "$SSH_PUBKEY"; ((ERRORS++)); }

# ─────────────────────────────────────────────────────────────────────
# KVM ACCESS
# ─────────────────────────────────────────────────────────────────────
[ -r /dev/kvm ] && [ -w /dev/kvm ] && printf "✓ /dev/kvm accessible\n" || { printf "✗ /dev/kvm not accessible\n"; ((ERRORS++)); }

# ─────────────────────────────────────────────────────────────────────
# RESOURCES
# ─────────────────────────────────────────────────────────────────────
DISK_AVAIL_GB=$(df -BG --output=avail . | tail -1 | tr -d ' G')
[ "$DISK_AVAIL_GB" -ge "${QCOW2_MIN_DISK_GB:-100}" ] && printf "✓ Disk: %sGB available\n" "$DISK_AVAIL_GB" || { printf "✗ Disk: %sGB (need %sGB)\n" "$DISK_AVAIL_GB" "${QCOW2_MIN_DISK_GB:-100}"; ((ERRORS++)); }

MEM_AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
[ "$MEM_AVAIL_MB" -ge "${QCOW2_MIN_MEM_MB:-8192}" ] && printf "✓ Memory: %sMB available\n" "$MEM_AVAIL_MB" || { printf "✗ Memory: %sMB (need %sMB)\n" "$MEM_AVAIL_MB" "${QCOW2_MIN_MEM_MB:-8192}"; ((ERRORS++)); }

echo ""
[ "$ERRORS" -eq 0 ] && echo "✓ Preflight passed" || { echo "✗ $ERRORS error(s)"; exit 1; }
```

---

### \_oci:nix

Build NixOS closure and capture nix_drv.

```sh {"name":"_oci:nix","tag":"requires:nix"}
set -e
if [ "${SKIP_NIX_BUILD:-false}" = "true" ] && [ -d result.writable ]; then
    echo "SKIP_NIX_BUILD: reusing existing"
    exit 0
fi

# Vendored inputs are required for offline builds.
if [ ! -f "_sources/catppuccin/flake.nix" ]; then
    echo "Error: vendored inputs missing. Run: runme run oci:vendor:inputs"
    exit 1
fi

# Update forked forgejo-runner to latest commit (optional - skip on network errors)
echo "Updating forgejo-runner-src flake input..."
if [ "${ALLOW_ONLINE_UPDATE:-false}" = "true" ]; then
    if ! nix flake update forgejo-runner-src --no-warn-dirty 2>/dev/null; then
        echo "  (skipped - network/SSL error, using cached input)"
    fi
else
    echo "  (skipped - offline mode)"
fi

# Build to ensure the output exists, then derive nix_drv from the output path.
OUT_PATH=$(nix build .#qcow2 --no-warn-dirty --no-link --print-out-paths | tail -1)
NIX_DRV_PATH=$(nix path-info --derivation "$OUT_PATH" 2>/dev/null | head -1 || true)
if [ -z "$NIX_DRV_PATH" ]; then
    echo "Error: nix path-info --derivation failed for $OUT_PATH"
    exit 1
fi
NIX_DRV=$(basename "$NIX_DRV_PATH" | cut -d- -f1)
echo "$NIX_DRV" > .nix_drv

nix build .#qcow2 --no-warn-dirty

BACKING_FILE="$(readlink -f result/nixos.qcow2)"
rm -rf result.writable && mkdir -p result.writable
qemu-img create -f qcow2 -b "$BACKING_FILE" -F qcow2 result.writable/nixos.qcow2
rm -f result && ln -sf result.writable result
chown -R "$(id -u):$(id -g)" result.writable/
```

---

### \_oci:cloudinit

Generate cloud-init ISO.

```sh {"name":"_oci:cloudinit"}
set -e
[ -n "$OVMF_CODE" ] || { echo "Error: OVMF_CODE not set"; exit 1; }
[ -n "$OVMF_VARS" ] || { echo "Error: OVMF_VARS not set"; exit 1; }

CLOUD_INIT_DIR="${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
mkdir -p "$CLOUD_INIT_DIR"

cp "$OVMF_VARS" "$CLOUD_INIT_DIR/OVMF_VARS.fd"
chmod 644 "$CLOUD_INIT_DIR/OVMF_VARS.fd"

cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: konductor-$(date +%s)
local-hostname: konductor
EOF

SSH_PUBKEY="${QCOW2_SSH_KEY_DIR:-$HOME/.ssh}/id_ed25519.pub"
[ -f "$SSH_PUBKEY" ] || { echo "Error: $SSH_PUBKEY not found"; exit 1; }

cat > "$CLOUD_INIT_DIR/user-data" << EOF
#cloud-config
users:
  - name: ${USER}
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
  - name: kc2
    groups: docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
  - name: kc2admin
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
  - name: runner
    groups: docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
write_files:
  - path: /var/lib/konductor/services.toml
    content: |
      [port_bases]
      ttyd = 7681
      vscode = 8080
      restty = 7685

      [user_services.kc2]
      ttyd = true
      vscode = true
      restty = false
    owner: root:root
    permissions: '0644'
runcmd:
  - echo "═══ cloud-init runcmd start ═══" > /dev/ttyS0
  - ls -lah /home/*/.ssh/ > /dev/ttyS0 2>&1 || true
  - echo "authorized_keys:" > /dev/ttyS0
  - wc -l /home/*/.ssh/authorized_keys > /dev/ttyS0 2>&1 || true
  - systemctl --failed --no-pager > /dev/ttyS0 2>&1 || true
  - journalctl -u konductor-pki-vm --no-pager -o short > /dev/ttyS0 2>&1 || true
  - journalctl -u konductor-pki-hypervisor --no-pager -o short > /dev/ttyS0 2>&1 || true
  - journalctl -u konductor-pki-bundle --no-pager -o short > /dev/ttyS0 2>&1 || true
  - PYTHONPATH=/opt/konductor/src/src python3 -m pki status > /dev/ttyS0 2>&1 || true
  - journalctl -u konductor-init --no-pager -o short > /dev/ttyS0 2>&1 || true
  - journalctl -u konductor --no-pager -o short > /dev/ttyS0 2>&1 || true
  - systemctl status 'konductor-vscode@*' 'konductor-ttyd@*' --no-pager > /dev/ttyS0 2>&1 || true
  - echo "═══ cloud-init runcmd complete ═══" > /dev/ttyS0
EOF

genisoimage -output "$CLOUD_INIT_DIR/seed.iso" \
    -volid cidata -joliet -rock -input-charset utf-8 \
    "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
```

---

### \_oci:img:reset

Reset image to pristine state.

```sh {"name":"_oci:img:reset","tag":"requires:guestfs"}
set -e
export LIBGUESTFS_BACKEND=direct
MOUNT="${QCOW2_MOUNT:-/tmp/nixmount}"

sudo mkdir -p "$MOUNT"
sudo guestmount -a result/nixos.qcow2 -m /dev/sda2 "$MOUNT"
trap 'sudo guestunmount "$MOUNT" 2>/dev/null || true; sudo rmdir "$MOUNT" 2>/dev/null || true' EXIT

sudo rm -f "$MOUNT"/etc/ssh/ssh_host_* "$MOUNT"/etc/machine-id
sudo rm -rf "$MOUNT"/var/lib/cloud "$MOUNT"/var/log/journal/*

sudo guestunmount "$MOUNT"
trap - EXIT
sync && sleep 1
sudo rmdir "$MOUNT" 2>/dev/null || true
```

---

### \_oci:vm:boot

Boot VM.

```sh {"name":"_oci:vm:boot","tag":"requires:kvm"}
set -e
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0

ss -tlnp 2>/dev/null | awk -v p=":${QCOW2_SSH_PORT:-2222} " '$0 ~ p {exit 0} END {exit 1}' && { echo "Error: Port ${QCOW2_SSH_PORT:-2222} in use"; exit 1; }

CLOUD_INIT_DIR="${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

qemu-system-x86_64 \
    -machine q35,accel=kvm,mem-merge=on \
    -m "${QCOW2_VM_MEMORY:-4096}" \
    -cpu host \
    -smp "${QCOW2_VM_CPUS:-4}" \
    -rtc base=utc,clock=host \
    -boot order=c,menu=off \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$CLOUD_INIT_DIR/OVMF_VARS.fd" \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2,cache=writeback,aio=io_uring,discard=unmap,detect-zeroes=unmap \
    -drive file="$CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,hostfwd=tcp::${QCOW2_SSH_PORT:-2222}-:22,hostfwd=tcp::8080-:8080,hostfwd=tcp::7681-:7681 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr,multidevs=remap \
    -virtfs local,path=/nix/store,mount_tag=nixstore,security_model=none,readonly=on \
    -daemonize \
    -pidfile "$PIDFILE" \
    -serial file:"${QCOW2_LOGFILE:-build-vm.log}" \
    -display none

sleep 1
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
    || { echo "QEMU failed"; exit 1; }
```

---

### \_oci:vm:wait

Wait for SSH.

```sh {"name":"_oci:vm:wait","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
timeout "${QCOW2_SSH_TIMEOUT:-300}" bash -c 'until ssh kc2admin@localhost true 2>/dev/null; do sleep 3; done' \
    || { echo "SSH timeout"; exit 1; }
```

---

### \_oci:vm:sync

Sync source to VM.

```sh {"name":"_oci:vm:sync"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -ex

COMMIT=$(git rev-parse --short HEAD)
BUNDLE="k9-${COMMIT}.bundle"

ssh kc2admin@localhost 'sudo rm -rf /opt/konductor && sudo mkdir -p /opt/konductor'

echo "Creating bundle ${BUNDLE}..."
git bundle create "/tmp/${BUNDLE}" HEAD --all

echo "Transferring bundle..."
scp "/tmp/${BUNDLE}" "kc2admin@localhost:/tmp/${BUNDLE}"
ssh kc2admin@localhost "sudo mv /tmp/${BUNDLE} /opt/konductor/${BUNDLE}"

echo "Cloning to /opt/konductor/src/..."
ssh kc2admin@localhost "sudo -E git clone /opt/konductor/${BUNDLE} /opt/konductor/src"
ssh kc2admin@localhost "cd /opt/konductor/src && sudo -E git checkout ${COMMIT}"

# Sync vendored inputs if present (required for offline flake evaluation)
if [ -d _sources ]; then
    rsync -a _sources/ "kc2admin@localhost:/tmp/_sources/"
    ssh kc2admin@localhost 'sudo rm -rf /opt/konductor/src/_sources && sudo mv /tmp/_sources /opt/konductor/src/_sources'
fi

DIRTY=$(ssh kc2admin@localhost 'cd /opt/konductor/src && git status --porcelain' || true)
if [ -n "$DIRTY" ]; then
    echo "WARNING: Tree is dirty after sync"
    echo "$DIRTY"
fi

ssh kc2admin@localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R kc2:kc2 /opt/konductor'
rm -f "/tmp/${BUNDLE}"

# Sync host's nix flake caches to VM for offline builds
# This includes gitv3 (git repos) and tarball-cache (flake input archives)
# Use root's cache since that's where the build caches are
echo "Syncing nix flake caches to VM..."
# Prime flake input cache from local artifacts only (no network).
# Offline pipeline requires full cache saturation every run.
echo "Priming host flake caches (offline)..."
if ! sudo -E env PATH="$PATH" HOME=/root XDG_CACHE_HOME=/root/.cache \
    nix --extra-experimental-features 'nix-command flakes' \
    flake archive --json --no-write-lock-file --offline . >/tmp/flake-archive.json; then
    echo "Error: missing flake inputs in local cache."
    echo "This pipeline requires a fully saturated local cache (no network)."
    exit 1
fi

# Extract store paths for flake inputs so we can copy them into the VM store.
jq -r '.. | objects | select(has("path")) | .path' /tmp/flake-archive.json \
  | sort -u > /tmp/flake-input-paths.txt
rm -f /tmp/flake-archive.json

# Seed VM store with flake inputs over SSH (no network).
echo "Seeding VM flake inputs (offline, ssh)..."
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
if ! sudo -E env PATH="$PATH" HOME=/root XDG_CACHE_HOME=/root/.cache NIX_SSHOPTS="-p ${SSH_PORT} -l kc2admin" \
    nix --extra-experimental-features 'nix-command flakes' \
    flake archive --no-write-lock-file --offline --to "ssh://localhost" .; then
    echo "Error: unable to seed VM store from local cache."
    echo "Ensure host cache is fully saturated and SSH to VM is available."
    exit 1
fi
unset SSH_PORT

# Copy flake input store paths into VM store via nix copy (offline).
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
NIX_SSHOPTS="-p ${SSH_PORT} -l kc2admin" \
  xargs -r nix copy --offline --to "ssh://localhost" < /tmp/flake-input-paths.txt
unset SSH_PORT
rm -f /tmp/flake-input-paths.txt

# Copy system closure to VM using nix-copy-closure (idiomatic approach).
# With system.includeBuildDependencies = true in the NixOS config, the runtime
# closure now INCLUDES all build-time dependencies (stdenv, bootstrap-tools, etc).
# This enables offline nixos-rebuild switch capability.
echo "Building system closure for VM seeding..."
SYSTEM_TOPLEVEL=$(nix build --no-link --print-out-paths .#nixosConfigurations.konductor.config.system.build.toplevel)
echo "Seeding VM with system closure: $SYSTEM_TOPLEVEL"
echo "  (includes build deps via system.includeBuildDependencies = true)"

# Count paths for visibility
CLOSURE_SIZE=$(nix path-info -r "$SYSTEM_TOPLEVEL" | wc -l)
echo "  Closure size: $CLOSURE_SIZE paths"

# Use nix-copy-closure - more idiomatic than manual path enumeration.
# This copies the full closure and registers paths in VM's nix database.
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
NIX_SSHOPTS="-o StrictHostKeyChecking=no -p ${SSH_PORT}" \
  nix-copy-closure --to kc2admin@localhost "$SYSTEM_TOPLEVEL"
unset SSH_PORT

if [ -d /root/.cache/nix ]; then
    # Root cache exists (from previous builds)
    ssh kc2admin@localhost 'sudo mkdir -p /root/.cache/nix'
    sudo rsync -a --info=progress2 /root/.cache/nix/ "kc2admin@localhost:/tmp/nix-cache/"
    ssh kc2admin@localhost 'sudo mv /tmp/nix-cache/* /root/.cache/nix/ 2>/dev/null || sudo cp -a /tmp/nix-cache/* /root/.cache/nix/'
    ssh kc2admin@localhost 'sudo rm -rf /tmp/nix-cache'
elif [ -d "$HOME/.cache/nix" ]; then
    # Fall back to user cache
    sudo mkdir -p /root/.cache
    sudo cp -a "$HOME/.cache/nix" /root/.cache/ 2>/dev/null || true
    ssh kc2admin@localhost 'mkdir -p ~/.cache/nix'
    rsync -a --info=progress2 "$HOME/.cache/nix/" "kc2admin@localhost:~/.cache/nix/"
    ssh kc2admin@localhost 'sudo mkdir -p /root/.cache && sudo cp -a ~/.cache/nix /root/.cache/'
fi

# Verify VM can resolve all flake inputs offline before rebuild.
echo "Validating VM flake inputs (offline)..."
if ! ssh kc2admin@localhost \
    "cd /opt/konductor/src && sudo -E env PATH=\"\$PATH\" HOME=/root XDG_CACHE_HOME=/root/.cache \
    nix --extra-experimental-features 'nix-command flakes' \
    --option substituters '' --option extra-substituters '' \
    flake archive --json --no-write-lock-file --offline . >/tmp/flake-archive.json"; then
    echo "Error: VM missing flake inputs for offline build."
    echo "Offline cache saturation failed."
    exit 1
fi

echo "✓ /opt/konductor/${BUNDLE} (bundle)"
echo "✓ /opt/konductor/src/ (cloned)"
echo "✓ /root/.cache/nix/ (flake caches)"
```

---

### \_oci:vm:rebuild

Run `nixos-rebuild switch` inside VM.

```sh {"name":"_oci:vm:rebuild","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

# Offline rebuild using paths copied via nix-copy-closure in _oci:vm:sync.
# With system.includeBuildDependencies = true, the full build closure
# (including stdenv, bootstrap-tools) is in the VM's local store.
# No substituter needed - paths are registered in VM's nix database.

echo "Running nixos-rebuild switch (offline)..."
ssh kc2admin@localhost "cd /opt/konductor/src && sudo -E env PATH=\"\$PATH\" HOME=/root XDG_CACHE_HOME=/root/.cache nixos-rebuild switch --flake .#konductor --offline 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Pre-build devshells to cache their closures (also offline)
echo "Pre-building devshells..."
ssh kc2admin@localhost "cd /opt/konductor/src && sudo -E env PATH=\"\$PATH\" HOME=/root XDG_CACHE_HOME=/root/.cache nix build --no-link --offline .#devShells.x86_64-linux.default 2>&1 || true"
ssh kc2admin@localhost "cd /opt/konductor/src && sudo -E env PATH=\"\$PATH\" HOME=/root XDG_CACHE_HOME=/root/.cache nix build --no-link --offline .#devShells.x86_64-linux.full 2>&1 || true"
ssh kc2admin@localhost "cd /opt/konductor/src && sudo -E env PATH=\"\$PATH\" HOME=/root XDG_CACHE_HOME=/root/.cache nix build --no-link --offline .#devShells.x86_64-linux.konductor 2>&1 || true"

echo "VM rebuilt from /opt/konductor/src flake"
```

---

### \_oci:vm:pki:test

Run PKI tests inside VM.

```sh {"name":"_oci:vm:pki:test"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

echo "Running PKI tests inside VM..."
ssh -o ConnectTimeout=10 kc2admin@localhost \
  'cd /opt/konductor/src/src && python3 -m pytest pki/ -v --tb=short --override-ini cache_dir=/tmp/pytest-cache 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

echo "PKI tests complete"
```

---

### \_oci:vm:pki:status

Display PKI certificate status.

```sh {"name":"_oci:vm:pki:status"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

echo "PKI certificate status:"
ssh -o ConnectTimeout=10 kc2admin@localhost \
  'PYTHONPATH=/opt/konductor/src/src python3 -m pki status 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### \_oci:vm:provenance

Write `/.konductor` inside VM.

```sh {"name":"_oci:vm:provenance"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -euo pipefail

# Gather provenance
GIT_COMMIT=$(git rev-parse HEAD) || { echo "✗ git rev-parse HEAD failed"; exit 1; }
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) || { echo "✗ git rev-parse --abbrev-ref HEAD failed"; exit 1; }
GIT_REMOTE=$(git remote get-url origin 2>/dev/null) || GIT_REMOTE="local"
NIX_VERSION=$(nix --version 2>/dev/null | head -1) || NIX_VERSION="unknown"
NIX_HASH=$(nix flake metadata --json 2>/dev/null | jq -r '.locked.narHash // "unknown"') || NIX_HASH="unknown"
NIX_DRV=$(cat .nix_drv 2>/dev/null) || NIX_DRV="unknown"
FLAKE_LOCK_SHA=$(sha256sum flake.lock 2>/dev/null | cut -d' ' -f1) || FLAKE_LOCK_SHA="unknown"
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ') || GIT_DIRTY="0"
BUILD_DATE=$(date -Iseconds) || { echo "✗ date failed"; exit 1; }
BUILD_HOST=$(hostname) || { echo "✗ hostname failed"; exit 1; }
BUILD_USER="${USER:?✗ USER not set}"
QEMU_VER=$(qemu-system-x86_64 --version 2>/dev/null | head -1 | sed 's/QEMU emulator version //') || QEMU_VER="unknown"

# Build host hardware identity
BUILD_HW_VENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n') || BUILD_HW_VENDOR=""
BUILD_HW_PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n') || BUILD_HW_PRODUCT=""
BUILD_HW_SERIAL=$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n') || BUILD_HW_SERIAL=""

OCI_IMAGE="${OCI_REGISTRY:-registry.ucs.arpa}/${OCI_IMAGE:-helix/flake}"

# Build tag list for provenance
OCI_TAGS="[\"${OCI_TAG:-latest-qcow2}\""
[ "$GIT_DIRTY" = "0" ] && OCI_TAGS+=", \"qcow2-${GIT_COMMIT:0:12}\""
OCI_TAGS+=", \"qcow2-${NIX_DRV:0:12}\""
OCI_TAGS+="]"

# Write /.konductor inside VM
ssh kc2admin@localhost "sudo tee /.konductor > /dev/null" << EOF
[konductor]
git_commit = "$GIT_COMMIT"
git_branch = "$GIT_BRANCH"
git_remote = "$GIT_REMOTE"
git_dirty = $GIT_DIRTY
nix_version = "$NIX_VERSION"
nix_hash = "$NIX_HASH"
nix_drv = "$NIX_DRV"
flake_lock_sha256 = "$FLAKE_LOCK_SHA"
build_date = "$BUILD_DATE"
build_host = "$BUILD_HOST"
build_user = "$BUILD_USER"
qemu = "$QEMU_VER"
build_hw_vendor = "$BUILD_HW_VENDOR"
build_hw_product = "$BUILD_HW_PRODUCT"
build_hw_serial = "$BUILD_HW_SERIAL"
strict = ${KONDUCTOR_STRICT:-false}
oci_image = "$OCI_IMAGE"
oci_tags = $OCI_TAGS
EOF
ssh kc2admin@localhost 'sudo chmod 644 /.konductor'

# Regenerate PKI certs with provenance
ssh kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki generate --force'
ssh kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki bundle'
ssh kc2admin@localhost 'PYTHONPATH=/opt/konductor/src/src python3 -m pki status' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Copy to host
ssh kc2admin@localhost 'cat /.konductor' > .konductor

# Display system state
ssh kc2admin@localhost 'ff 2>/dev/null || fastfetch 2>/dev/null || true'
```

---

### \_oci:vm:gc

Garbage collect.

```sh {"name":"_oci:vm:gc"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e
ssh kc2admin@localhost 'sudo nix-collect-garbage -d'
ssh kc2admin@localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
ssh kc2admin@localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

---

### \_oci:vm:zero

Zero free space.

```sh {"name":"_oci:vm:zero","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
ssh kc2admin@localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

---

### \_oci:vm:halt

Shutdown VM.

```sh {"name":"_oci:vm:halt"}
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
[ -f "$PIDFILE" ] || exit 0

PID=$(cat "$PIDFILE")
if kill -0 "$PID" 2>/dev/null; then
    ssh kc2admin@localhost 'sudo poweroff' 2>/dev/null || true
    sleep 5
    kill "$PID" 2>/dev/null || true
fi
rm -f "$PIDFILE"
```

---

### \_oci:img:clean

Clean credentials from image.

```sh {"name":"_oci:img:clean","tag":"requires:guestfs"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e
export LIBGUESTFS_BACKEND=direct
MOUNT="${QCOW2_MOUNT:-/tmp/nixmount}"

sudo mkdir -p "$MOUNT"
sudo guestmount -a result/nixos.qcow2 -m /dev/sda2 "$MOUNT"
trap 'sudo guestunmount "$MOUNT" 2>/dev/null || true; sudo rmdir "$MOUNT" 2>/dev/null || true' EXIT

sudo rm -f "$MOUNT"/etc/ssh/ssh_host_* "$MOUNT"/etc/machine-id
sudo rm -rf "$MOUNT"/var/lib/cloud "$MOUNT"/var/log/journal/*
sudo rm -rf "$MOUNT"/root/.ssh "$MOUNT"/home/*/.ssh 2>/dev/null || true
sudo rm -f "$MOUNT"/root/.gitconfig "$MOUNT"/home/*/.gitconfig 2>/dev/null || true

sudo guestunmount "$MOUNT"
trap - EXIT
sync && sleep 1
sudo rmdir "$MOUNT" 2>/dev/null || true
```

---

### \_oci:img:compress

ZSTD compress.

```sh {"name":"_oci:img:compress","tag":"duration:slow"}
set -e
if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    cp result/nixos.qcow2 konductor.qcow2
    exit 0
fi
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 konductor.qcow2.tmp
```

---

### \_oci:img:sparsify

Sparsify image.

```sh {"name":"_oci:img:sparsify","tag":"duration:slow,requires:guestfs"}
set -e
if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    exit 0
fi
export LIBGUESTFS_BACKEND=direct
sudo -E virt-sparsify --compress --convert qcow2 -o compression_type=zstd konductor.qcow2.tmp konductor.qcow2
rm -f konductor.qcow2.tmp
```

---

### \_oci:tmp:clean

Remove temporary files.

```sh {"name":"_oci:tmp:clean"}
rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -f .nix_drv
```

---

### \_oci:verify

Append post-seal fields to .konductor.

```sh {"name":"_oci:verify","tag":"type:readonly"}
set -e
[ -f konductor.qcow2 ] || { echo "Error: konductor.qcow2 not found"; exit 1; }
[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

IMAGE_SHA256=$(sha256sum konductor.qcow2 | cut -d' ' -f1)
IMAGE_SIZE=$(ls -lh konductor.qcow2 | awk '{print $5}')
cat >> .konductor << EOF
image_sha256 = "$IMAGE_SHA256"
image_size = "$IMAGE_SIZE"
EOF

cat .konductor
```

---

## Debug Tools

### oci:debug:log

View boot log.

```sh {"name":"oci:debug:log","excludeFromRunAll":"true","tag":"type:debug"}
tail -100 "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### oci:vm:kill

Force kill VM.

```sh {"name":"oci:vm:kill","excludeFromRunAll":"true","tag":"type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
```
