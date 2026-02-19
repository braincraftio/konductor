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

This file is intended to be self-contained and should not require the parent workspace or mise
tasks.

Use directly from `${WORKSPACE_ROOT}/flake` or `/opt/konductor/src` without external dependencies.

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

# Or run individual steps
runme run oci:clean
runme run oci:image
runme run oci:container

# Push to registry
runme run oci:push
```

---

## Environment Variables

Set these in `.env` or export before running:

```bash
# Registry configuration
export OCI_REGISTRY="registry.docker.arpa"
export OCI_IMAGE="braincraft/konductor"
export OCI_TAG="latest-qcow2"

# VM port forwarding (host ports, avoid conflicts with host services)
export QCOW2_SSH_PORT=2222       # SSH access
export QCOW2_TTYD_PORT=17681     # TTYD terminal (guest :7681)
export QCOW2_VSCODE_PORT=18080   # VS Code server (guest :8080)

# Optional: Skip phases for iteration
export SKIP_VM_PHASE=false
export SKIP_COMPRESS=false
export SKIP_NIX_BUILD=false
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

```bash {"name":"oci:build","excludeFromRunAll":"true","tag":"type:entry"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  oci:build - Standalone QCOW2 + OCI Build Pipeline"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Target: ${OCI_REGISTRY:-registry.ucs.arpa}/${OCI_IMAGE:-braincraft/konductor}:${OCI_TAG:-latest-qcow2}"
echo ""

OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"

echo "▶ Phase 1: Clean..."
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:clean

echo ""
echo "▶ Phase 2: Build QCOW2 image..."
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:image

echo ""
echo "▶ Phase 3: Package as containerDisk..."
runme run --direnv=true --load-env=true --filename "$OCI_BUILD_FILE" oci:container

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ Build complete!"
echo "═══════════════════════════════════════════════════════════════════════════"
cat .konductor
```

---

## oci:image

Build QCOW2: nix → VM configure → seal → verify.

```bash {"name":"oci:image","excludeFromRunAll":"true","tag":"type:entry"}
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
    runme run --direnv=true --filename "$OCI_BUILD_FILE" "$phase"
done
```

---

## oci:container

Package QCOW2 as containerDisk.

```bash {"name":"oci:container","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
if ! eval "$(nix print-dev-env .#konductor)"; then
    echo "Warning: nix print-dev-env failed, using current environment"
fi
echo "DEBUG: which docker=$(which docker)"
echo "DEBUG: docker buildx version=$(docker buildx version 2>&1)"
echo "DEBUG: PATH (first 20):" && echo "$PATH" | tr ':' '\n' | head -20 || true
REGISTRY="${OCI_REGISTRY:-registry.ucs.arpa}"
IMAGE="${OCI_IMAGE:-braincraft/konductor}"
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

# Apply all tags from .konductor so CI output matches reality
# Parse oci_tags array from .konductor TOML and create docker tags
OCI_TAGS_LINE=$(grep '^oci_tags = ' .konductor | sed 's/^oci_tags = //')
# Extract tags from JSON array: ["tag1", "tag2", ...] -> tag1 tag2 ...
TAGS=$(echo "$OCI_TAGS_LINE" | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$')

echo "Applying tags:"
for tag in $TAGS; do
    if [ "$tag" != "$TAG" ]; then
        docker tag "$FULL_IMAGE" "$REGISTRY/$IMAGE:$tag"
        echo "  ✓ $REGISTRY/$IMAGE:$tag"
    fi
done

echo "✓ Built: $FULL_IMAGE"
```

---

## oci:push

Push container with multi-tag (git/nix/latest).

```bash {"name":"oci:push","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
REGISTRY="${OCI_REGISTRY:-registry.ucs.arpa}"
IMAGE="${OCI_IMAGE:-braincraft/konductor}"
BASE_TAG="${OCI_TAG:-latest-qcow2}"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)
flake_lock_sha=$(sed -n 's/^flake_lock_sha256 = "\(.*\)"$/\1/p' .konductor)

# Build tag list - full hashes, dirty indicator when tree is dirty
TAGS=("$BASE_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("qcow2-${git_commit}")
else
    TAGS+=("qcow2-dirty")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("qcow2-${nix_drv}")
fi
if [ -n "$flake_lock_sha" ] && [ "$flake_lock_sha" != "unknown" ]; then
    TAGS+=("qcow2-flake-${flake_lock_sha}")
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

```bash {"name":"oci:clean","excludeFromRunAll":"true","tag":"type:destructive"}
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo umount -f "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
fusermount -uz "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
sudo rm -rf "${QCOW2_MOUNT:-/tmp/nixmount}" "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
sudo rm -rf result result.writable konductor.qcow2 konductor.qcow2.tmp .konductor .nix_drv .system-toplevel
echo "✓ Clean"
```

---

## oci:start

Boot image for local development.

```bash {"name":"oci:start","excludeFromRunAll":"true","tag":"type:entry"}
set -e
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. Use: ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
    exit 0
fi
[ -f result/nixos.qcow2 ] || { echo "No image. Run oci:image first."; exit 1; }

# Clean VM runtime state only (not the image)
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:cloudinit
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:boot
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:wait
echo "VM ready: ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
```

---

## oci:ssh

```bash {"name":"oci:ssh","excludeFromRunAll":"true","tag":"type:entry"}
ssh -p "${QCOW2_SSH_PORT:-2222}" kc2admin@localhost
```

---

## oci:stop

```bash {"name":"oci:stop","excludeFromRunAll":"true","tag":"type:entry"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:halt
```

---

## oci:vendor:inputs

Vendor all flake inputs into `./_sources` for fully offline builds.

```bash {"name":"oci:vendor:inputs","excludeFromRunAll":"true","tag":"type:entry"}
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
  rsync -a --chmod=Du+w,Fu+w "$store_path/" "_sources/$name/"
done < /tmp/vendor-lock.jsonl

rm -f /tmp/vendor-lock.jsonl
unset XDG_CACHE_HOME HOME

# NOTE: We do NOT run 'nix flake lock' here.
# The committed flake.lock has github refs; keep it that way for future vendor runs.
# When building with 'path:.#konductor', nix resolves the path inputs from flake.nix
# without needing to update flake.lock (use --no-write-lock-file to prevent changes).

echo "✓ Vendored inputs into ./_sources"
ls _sources/
```

---

## oci:vendor:inputs:online

Intermittent online refresh: update lock from network, then vendor into `./_sources`, then re-lock
to local paths for offline builds.

```bash {"name":"oci:vendor:inputs:online","excludeFromRunAll":"true","tag":"type:entry"}
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
runme run oci:vendor:inputs

echo "✓ Online refresh complete: flake.lock + _sources updated for offline use"
```

---

---

## Pipeline Tasks

### \_oci:preflight

Validate environment (standalone - no cluster required).

```bash {"name":"_oci:preflight"}
set -e

# Build host system state
if command -v ff &>/dev/null; then
    ff
elif command -v fastfetch &>/dev/null; then
    fastfetch
else
    echo "(fastfetch not available)"
fi

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

REQUIRED_BINS="${QCOW2_REQUIRED_BINS:-nix qemu-img qemu-system-x86_64 passt genisoimage guestmount guestunmount virt-sparsify ssh rsync timeout ss du sha256sum jq docker}"

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
if FLAKE_META=$(nix flake metadata . --no-write-lock-file --json 2>/dev/null); then
    echo "$FLAKE_META" | jq '{
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
    }'
else
    echo "  (skipped - flake metadata failed)"
fi

echo ""
echo "Flake outputs:"
if FLAKE_SHOW=$(nix flake show . --json 2>/dev/null); then
    echo "$FLAKE_SHOW" | jq 'keys'
else
    echo "  (skipped - flake show failed)"
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
SSH_KEY="${QCOW2_SSH_KEY_DIR:-$HOME/.ssh}/id_ed25519"
SSH_PUBKEY="${SSH_KEY}.pub"
if ! ssh-keygen -l -f "$SSH_PUBKEY" &>/dev/null; then
    echo "  No SSH key found, generating..."
    mkdir -p "$(dirname "$SSH_KEY")"
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q
fi
printf "✓ SSH key: %s\n" "$SSH_PUBKEY"

# ─────────────────────────────────────────────────────────────────────
# KVM ACCESS
# ─────────────────────────────────────────────────────────────────────
[ -r /dev/kvm ] && [ -w /dev/kvm ] && printf "✓ /dev/kvm accessible\n" || { printf "✗ /dev/kvm not accessible\n"; ((ERRORS++)); }

# ─────────────────────────────────────────────────────────────────────
# PORT AVAILABILITY
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Port availability:"
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
VSCODE_PORT="${QCOW2_VSCODE_PORT:-18080}"
TTYD_PORT="${QCOW2_TTYD_PORT:-17681}"

for port_var in "SSH_PORT:$SSH_PORT" "VSCODE_PORT:$VSCODE_PORT" "TTYD_PORT:$TTYD_PORT"; do
    name="${port_var%%:*}"
    port="${port_var##*:}"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        proc=$(ss -tlnp 2>/dev/null | grep ":${port} " | sed 's/.*users:(("\([^"]*\)".*/\1/' | head -1)
        printf "✗ %-12s port %s in use by %s\n" "$name" "$port" "$proc"
        ((ERRORS++))
    else
        printf "✓ %-12s port %s available\n" "$name" "$port"
    fi
done

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

```bash {"name":"_oci:nix","tag":"requires:nix"}
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
    if UPDATE_OUT=$(nix flake update forgejo-runner-src --no-warn-dirty 2>&1); then
        echo "  Updated: $UPDATE_OUT"
    else
        echo "  (skipped - network/SSL error: ${UPDATE_OUT:0:100})"
    fi
else
    echo "  (skipped - offline mode)"
fi

# Build qcow2 image (shows real-time progress, no output buffering)
echo "Building .#qcow2..."
nix build .#qcow2 --no-warn-dirty

# Get output path and derivation hash after build completes
OUT_PATH=$(nix build .#qcow2 --no-warn-dirty --no-link --print-out-paths | head -1)
if [ -z "$OUT_PATH" ]; then
    echo "Error: nix build --print-out-paths returned empty"
    exit 1
fi
NIX_DRV_PATH=$(nix path-info --derivation "$OUT_PATH" | head -1)
if [ -z "$NIX_DRV_PATH" ]; then
    echo "Error: nix path-info --derivation failed for $OUT_PATH"
    exit 1
fi
NIX_DRV=$(basename "$NIX_DRV_PATH" | cut -d- -f1)
echo "$NIX_DRV" > .nix_drv
echo "Build complete: $OUT_PATH"

BACKING_FILE="$(readlink -f result/nixos.qcow2)"
rm -rf result.writable && mkdir -p result.writable
qemu-img create -f qcow2 -b "$BACKING_FILE" -F qcow2 result.writable/nixos.qcow2
rm -f result && ln -sf result.writable result
chown -R "$(id -u):$(id -g)" result.writable/
```

---

### \_oci:cloudinit

Generate cloud-init ISO.

```bash {"name":"_oci:cloudinit"}
set -e
[ -n "$OVMF_CODE" ] || { echo "Error: OVMF_CODE not set"; exit 1; }
[ -n "$OVMF_VARS" ] || { echo "Error: OVMF_VARS not set"; exit 1; }

CLOUD_INIT_DIR="${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -rf "$CLOUD_INIT_DIR"
mkdir -p "$CLOUD_INIT_DIR"

cp "$OVMF_VARS" "$CLOUD_INIT_DIR/OVMF_VARS.fd"
chmod 644 "$CLOUD_INIT_DIR/OVMF_VARS.fd"

cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: konductor-$(date +%s)
local-hostname: konductor
EOF

SSH_PUBKEY="${QCOW2_SSH_KEY_DIR:-$HOME/.ssh}/id_ed25519.pub"
[ -f "$SSH_PUBKEY" ] || { echo "Error: $SSH_PUBKEY not found"; exit 1; }

cat > "$CLOUD_INIT_DIR/user-data" << 'EOF'
#cloud-config
users:
  - name: PLACEHOLDER_USER
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - PLACEHOLDER_PUBKEY
  - name: kc2
    groups: docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - PLACEHOLDER_PUBKEY
  - name: kc2admin
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - PLACEHOLDER_PUBKEY
  - name: runner
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - PLACEHOLDER_PUBKEY
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
  - echo "═══ Cloud-init configuration ═══" > /dev/ttyS0
  - echo "--- user-data ---" > /dev/ttyS0
  - cat /var/lib/cloud/instance/user-data.txt > /dev/ttyS0 2>&1 || echo "user-data not found" > /dev/ttyS0
  - echo "--- network-config ---" > /dev/ttyS0
  - cat /var/lib/cloud/instance/network-config > /dev/ttyS0 2>&1 || echo "network-config not found" > /dev/ttyS0
  - echo "--- cloud-init status ---" > /dev/ttyS0
  - cloud-init status --long > /dev/ttyS0 2>&1 || true
  - echo "═══ Network preflight checks ═══" > /dev/ttyS0
  - 'ip route show > /dev/ttyS0 2>&1 || { echo "PREFLIGHT FAILED: no routes" > /dev/ttyS0; exit 1; }'
  - 'ip route | grep -q default || { echo "PREFLIGHT FAILED: no default route" > /dev/ttyS0; exit 1; }'
  - 'nslookup cache.nixos.org > /dev/ttyS0 2>&1 || { echo "PREFLIGHT FAILED: DNS resolution failed" > /dev/ttyS0; exit 1; }'
  - 'if [ -f /etc/konductor/proxy.env ]; then source /etc/konductor/proxy.env && PROXY_HOST=$(echo $http_proxy | sed "s|http://||" | cut -d: -f1) && PROXY_PORT=$(echo $http_proxy | sed "s|http://||" | cut -d: -f2) && nc -zv -w 5 $PROXY_HOST $PROXY_PORT > /dev/ttyS0 2>&1 || { echo "PREFLIGHT FAILED: proxy $PROXY_HOST:$PROXY_PORT unreachable" > /dev/ttyS0; exit 1; }; fi'
  - 'curl -I --connect-timeout 5 https://cache.nixos.org/nix-cache-info > /dev/ttyS0 2>&1 || { echo "PREFLIGHT FAILED: cannot reach cache.nixos.org" > /dev/ttyS0; exit 1; }'
  - echo "═══ Network preflight PASSED ═══" > /dev/ttyS0
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

# Replace placeholders
sed -i "s/PLACEHOLDER_USER/${USER}/g" "$CLOUD_INIT_DIR/user-data"
sed -i "s|PLACEHOLDER_PUBKEY|$(cat "$SSH_PUBKEY")|g" "$CLOUD_INIT_DIR/user-data"

# Add proxy configuration if it exists
if [ -f /etc/konductor/proxy.env ]; then
    echo "Detected proxy configuration, adding to cloud-init"
    # Create temp file with proxy write_files entry
    {
        echo "  - path: /etc/konductor/proxy.env"
        echo "    content: |"
        sed 's/^/      /' /etc/konductor/proxy.env
        echo "    owner: root:root"
        echo "    permissions: '0644'"
    } > "$CLOUD_INIT_DIR/proxy.tmp"
    # Insert before runcmd
    sed -i '/^runcmd:/e cat '"$CLOUD_INIT_DIR/proxy.tmp" "$CLOUD_INIT_DIR/user-data"
    rm -f "$CLOUD_INIT_DIR/proxy.tmp"
fi

genisoimage -output "$CLOUD_INIT_DIR/seed.iso" \
    -volid cidata -joliet -rock -input-charset utf-8 \
    "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
```

---

### \_oci:img:reset

Reset image to pristine state.

```bash {"name":"_oci:img:reset","tag":"requires:guestfs"}
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

```bash {"name":"_oci:vm:boot","tag":"requires:kvm"}
set -e
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0

# Ports (validated in preflight)
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
VSCODE_PORT="${QCOW2_VSCODE_PORT:-18080}"
TTYD_PORT="${QCOW2_TTYD_PORT:-17681}"

CLOUD_INIT_DIR="${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

# Calculate CPUs: all cores minus 2, minimum 2
TOTAL_CPUS=$(nproc)
VM_CPUS=$((TOTAL_CPUS - 2))
[ "$VM_CPUS" -lt 2 ] && VM_CPUS=2

echo "Allocating ${VM_CPUS} CPUs to build VM (host has ${TOTAL_CPUS})"

# TODO: Switch to passt networking once the image includes it (konductor.nix has passt added)
# passt provides better performance and modern rootless networking vs QEMU user mode
# For now using user mode (restrict=off) since host VM doesn't have passt until next rebuild
qemu-system-x86_64 \
    -machine q35,accel=kvm,mem-merge=on \
    -m "${QCOW2_VM_MEMORY:-8192}" \
    -cpu host \
    -smp "${QCOW2_VM_CPUS:-$VM_CPUS}" \
    -rtc base=utc,clock=host \
    -boot order=c,menu=off \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$CLOUD_INIT_DIR/OVMF_VARS.fd" \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2,cache=writeback,aio=io_uring,discard=unmap,detect-zeroes=unmap \
    -drive file="$CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,restrict=off,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${VSCODE_PORT}-:8080,hostfwd=tcp::${TTYD_PORT}-:7681 \
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
    || { echo "QEMU failed to start"; tail -20 "${QCOW2_LOGFILE:-build-vm.log}"; exit 1; }

echo "VM started: SSH=$SSH_PORT, VSCode=$VSCODE_PORT, TTYD=$TTYD_PORT"
```

---

### \_oci:vm:wait

Wait for SSH.

```bash {"name":"_oci:vm:wait","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
TIMEOUT="${QCOW2_SSH_TIMEOUT:-300}"
START_TIME=$(date +%s)
RETRY_COUNT=0

echo "Waiting for SSH on port $SSH_PORT (timeout: ${TIMEOUT}s)..."
echo "Start time: $(date '+%Y-%m-%d %H:%M:%S')"

while true; do
    if ssh -p $SSH_PORT -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null kc2admin@localhost true 2>/dev/null; then
        echo "SSH connection successful after ${RETRY_COUNT} retries ($(( $(date +%s) - START_TIME ))s elapsed)"
        break
    fi

    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "SSH timeout after ${TIMEOUT}s (${RETRY_COUNT} retries) on port $SSH_PORT"
        exit 1
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "  Retry ${RETRY_COUNT}: SSH not ready yet (${ELAPSED}s elapsed, $(( TIMEOUT - ELAPSED ))s remaining)"
    sleep 3
done
```

---

### \_oci:vm:sync

Sync source to VM.

```bash {"name":"_oci:vm:sync"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

COMMIT=$(git rev-parse --short HEAD)
BUNDLE="k9-${COMMIT}.bundle"

ssh $SSH_OPTS kc2admin@localhost 'sudo rm -rf /opt/konductor && sudo mkdir -p /opt/konductor'

# git bundle: portable repo with full history
echo "Creating bundle ${BUNDLE}..."
git bundle create "/tmp/${BUNDLE}" HEAD --all

# Transfer bundle
echo "Transferring bundle..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "/tmp/${BUNDLE}" "kc2admin@localhost:/tmp/${BUNDLE}"
ssh $SSH_OPTS kc2admin@localhost "sudo mv /tmp/${BUNDLE} /opt/konductor/${BUNDLE}"

# Clone from bundle (creates clean repo with history)
echo "Cloning to /opt/konductor/src/..."
ssh $SSH_OPTS kc2admin@localhost "sudo -E git clone /opt/konductor/${BUNDLE} /opt/konductor/src"
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && sudo -E git checkout ${COMMIT}"

# Sync vendored inputs if present (required for offline flake evaluation)
if [ -d _sources ]; then
    rsync -e "ssh $SSH_OPTS" -a _sources/ "kc2admin@localhost:/tmp/_sources/"
    ssh $SSH_OPTS kc2admin@localhost 'sudo rm -rf /opt/konductor/src/_sources && sudo mv /tmp/_sources /opt/konductor/src/_sources'
fi

# Verify clean state
DIRTY=$(ssh $SSH_OPTS kc2admin@localhost 'cd /opt/konductor/src && git status --porcelain' || true)
if [ -n "$DIRTY" ]; then
    echo "WARNING: Tree is dirty after sync"
    echo "$DIRTY"
fi

ssh $SSH_OPTS kc2admin@localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R kc2:kc2 /opt/konductor'
rm -f "/tmp/${BUNDLE}"

echo "✓ /opt/konductor/${BUNDLE} (bundle)"
echo "✓ /opt/konductor/src/ (cloned)"
```

---

### \_oci:vm:rebuild

Run `nixos-rebuild switch` inside VM to build the environment natively.

This ensures:

- Full Konductor environment is built natively inside the VM
- All nix store paths are pre-cached for airgap use
- The VM can reproduce itself from /opt/konductor/src

```bash {"name":"_oci:vm:rebuild","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Generate --override-input flags from _sources/ contents (offline builds)
# This redirects github inputs in flake.nix to local vendored paths
OVERRIDE_INPUTS=""
if ssh $SSH_OPTS kc2admin@localhost '[ -d /opt/konductor/src/_sources/nixpkgs ]'; then
    echo "Using vendored inputs from _sources/ for offline build..."
    OVERRIDE_INPUTS=$(ssh $SSH_OPTS kc2admin@localhost 'for dir in /opt/konductor/src/_sources/*/; do input=$(basename "$dir"); echo -n " --override-input $input path:./_sources/$input"; done')
fi

# Stop cloud-init services before rebuild to prevent restart failures
# Cloud-init services are oneshot boot services that fail when reactivated
ssh kc2admin@localhost "sudo systemctl stop cloud-config.service cloud-final.service cloud-init-local.service cloud-init.service 2>/dev/null || true"

# Rebuild NixOS from the synced flake
# path:. includes gitignored _sources/, --no-write-lock-file preserves committed lock
# Rebuild NixOS with proxy support
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nixos-rebuild switch --flake 'path:.#konductor' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Pre-build devshells to cache their closures with proxy support
# This ensures `nix develop` works offline - failures here break offline support
echo "Caching devshells for offline use..."
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link 'path:.#devShells.x86_64-linux.default' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.default failed"; exit 1; }
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link 'path:.#devShells.x86_64-linux.full' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.full failed"; exit 1; }
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link 'path:.#devShells.x86_64-linux.konductor' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.konductor failed"; exit 1; }
echo "✓ Devshells cached"

echo "VM rebuilt from /opt/konductor/src flake"
```

---

### \_oci:vm:pki:test

Run PKI tests inside VM.

```bash {"name":"_oci:vm:pki:test"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Running PKI tests inside VM..."
ssh $SSH_OPTS kc2admin@localhost \
  'cd /opt/konductor/src/src && python3 -m pytest pki/ -v --tb=short --override-ini cache_dir=/tmp/pytest-cache 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

echo "PKI tests complete"
```

---

### \_oci:vm:pki:status

Display PKI certificate status.

```bash {"name":"_oci:vm:pki:status"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "PKI certificate status:"
ssh $SSH_OPTS kc2admin@localhost \
  'PYTHONPATH=/opt/konductor/src/src python3 -m pki status 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### \_oci:vm:provenance

Write `/.konductor` inside VM.

```bash {"name":"_oci:vm:provenance"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -euo pipefail

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Gather provenance - ORPHANED for missing git remote, FAIL HARD for broken tools
GIT_COMMIT=$(git rev-parse HEAD) || { echo "✗ git rev-parse HEAD failed"; exit 1; }
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) || { echo "✗ git rev-parse --abbrev-ref HEAD failed"; exit 1; }
GIT_REMOTE=$(git remote get-url origin 2>/dev/null) || { echo "⚠ ORPHANED: no git remote origin"; GIT_REMOTE="ORPHANED"; }
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')

# Nix provenance - MUST work or build is broken (stderr goes to log, stdout is JSON)
NIX_VERSION=$(nix --version | head -1) || { echo "✗ nix --version failed"; exit 1; }
NIX_META=$(nix flake metadata --json) || { echo "✗ nix flake metadata --json failed"; exit 1; }
NIX_HASH=$(echo "$NIX_META" | jq -r '.locked.narHash') || { echo "✗ jq parse of flake metadata failed"; exit 1; }
[ -n "$NIX_HASH" ] && [ "$NIX_HASH" != "null" ] || { echo "✗ narHash not found in flake metadata"; exit 1; }

# Build artifacts - MUST exist from prior phases
NIX_DRV=$(cat .nix_drv) || { echo "✗ .nix_drv not found (did _oci:nix run?)"; exit 1; }
FLAKE_LOCK_SHA=$(sha256sum flake.lock | cut -d' ' -f1) || { echo "✗ sha256sum flake.lock failed"; exit 1; }

# Build environment - MUST be available
BUILD_DATE=$(date -Iseconds) || { echo "✗ date failed"; exit 1; }
BUILD_HOST=$(hostname) || { echo "✗ hostname failed"; exit 1; }
BUILD_USER="${USER:?✗ USER not set}"
QEMU_VER=$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //') || { echo "✗ qemu-system-x86_64 --version failed"; exit 1; }

# Build host hardware identity - empty if inaccessible (VM/container builds)
BUILD_HW_VENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n') || BUILD_HW_VENDOR=""
BUILD_HW_PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n') || BUILD_HW_PRODUCT=""
BUILD_HW_SERIAL=$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n') || BUILD_HW_SERIAL=""

OCI_IMAGE="${OCI_REGISTRY:-registry.ucs.arpa}/${OCI_IMAGE:-braincraft/konductor}"

# Build tag list for provenance - full hashes, dirty indicator when tree is dirty
OCI_TAGS="[\"${OCI_TAG:-latest-qcow2}\""
if [ "$GIT_DIRTY" = "0" ]; then
    OCI_TAGS+=", \"qcow2-${GIT_COMMIT}\""
else
    OCI_TAGS+=", \"qcow2-dirty\""
fi
OCI_TAGS+=", \"qcow2-${NIX_DRV}\""
[ -n "$FLAKE_LOCK_SHA" ] && [ "$FLAKE_LOCK_SHA" != "unknown" ] && OCI_TAGS+=", \"qcow2-flake-${FLAKE_LOCK_SHA}\""
OCI_TAGS+="]"

# Write /.konductor inside VM
ssh $SSH_OPTS kc2admin@localhost "sudo tee /.konductor > /dev/null" << EOF
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
ssh $SSH_OPTS kc2admin@localhost 'sudo chmod 644 /.konductor'

# Regenerate PKI certs with provenance
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki generate --force'
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki bundle'
ssh $SSH_OPTS kc2admin@localhost 'PYTHONPATH=/opt/konductor/src/src python3 -m pki status' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Copy to host
ssh $SSH_OPTS kc2admin@localhost 'cat /.konductor' > .konductor

# Display system state - ff MUST exist in Konductor
ssh $SSH_OPTS kc2admin@localhost 'ff' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### \_oci:vm:gc

Garbage collect.

```bash {"name":"_oci:vm:gc"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh $SSH_OPTS kc2admin@localhost 'sudo nix-collect-garbage -d'
ssh $SSH_OPTS kc2admin@localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
ssh $SSH_OPTS kc2admin@localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

---

### \_oci:vm:zero

Zero free space.

```bash {"name":"_oci:vm:zero","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh $SSH_OPTS kc2admin@localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

---

### \_oci:vm:halt

Shutdown VM.

```bash {"name":"_oci:vm:halt"}
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
[ -f "$PIDFILE" ] || exit 0

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

PID=$(cat "$PIDFILE")
if kill -0 "$PID" 2>/dev/null; then
    ssh $SSH_OPTS kc2admin@localhost 'sudo poweroff' 2>/dev/null || true
    sleep 5
    kill "$PID" 2>/dev/null || true
fi
rm -f "$PIDFILE"
```

---

### \_oci:img:clean

Clean credentials from image.

```bash {"name":"_oci:img:clean","tag":"requires:guestfs"}
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

ZSTD compress and sparsify image.

Note: SKIP_COMPRESS=true produces a larger, uncompressed image (faster builds, larger output).

```bash {"name":"_oci:img:compress","tag":"duration:slow"}
set -e

# Cap coroutines to prevent excessive memory usage on high-core systems
CORES=$(nproc)
[ "$CORES" -gt 16 ] && CORES=16

if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    echo "SKIP_COMPRESS: copying uncompressed image..."
    cp result/nixos.qcow2 konductor.qcow2
else
    echo "Compressing with qemu-img (zstd, ${CORES} coroutines)..."
    qemu-img convert -c -p -m "$CORES" -O qcow2 -o compression_type=zstd result/nixos.qcow2 konductor.qcow2.tmp
fi
```

---

### \_oci:img:sparsify

Sparsify image (skipped if SKIP_COMPRESS=true).

```bash {"name":"_oci:img:sparsify","tag":"duration:slow,requires:guestfs"}
set -e

if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    echo "SKIP_COMPRESS: skipping sparsify (image already final)"
    exit 0
fi

[ -f konductor.qcow2.tmp ] || { echo "Error: konductor.qcow2.tmp not found (compress phase failed?)"; exit 1; }

echo "Sparsifying with virt-sparsify..."
export LIBGUESTFS_BACKEND=direct
sudo -E virt-sparsify --compress --convert qcow2 -o compression_type=zstd konductor.qcow2.tmp konductor.qcow2
rm -f konductor.qcow2.tmp
```

---

### \_oci:tmp:clean

Remove temporary files.

```bash {"name":"_oci:tmp:clean"}
rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -f .nix_drv .system-toplevel
```

---

### \_oci:verify

Append post-seal fields to .konductor.

```bash {"name":"_oci:verify","tag":"type:readonly"}
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

```bash {"name":"oci:debug:log","excludeFromRunAll":"true","tag":"type:debug"}
bat "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### oci:vm:kill

Force kill VM.

```bash {"name":"oci:vm:kill","excludeFromRunAll":"true","tag":"type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
```
