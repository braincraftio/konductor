---
cwd: ../..
shell: bash
skipPrompts: true
tag: k9:ci:test
runme:
  version: v3
---

# Test: provenance → gc env corruption

```bash {"name":"k9:ci:test:before","tag":"k9:ci:test,test:env"}
echo "BEFORE: HOME=$HOME"
echo "BEFORE: PATH=$PATH"
```

```bash {"name":"k9:ci:test:provenance","tag":"k9:ci:test,test:env"}
set -eo pipefail
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP_OPTS="-P $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

_commit=$(git rev-parse HEAD)
_branch=$(git rev-parse --abbrev-ref HEAD)
_remote=$(git remote get-url origin 2>/dev/null || echo ORPHANED)
_dirty=$(git status --porcelain | wc -l | tr -d ' ')
_nix_ver=$(nix --version | head -1)
_nix_hash=$(nix flake metadata --json | jq -r '.locked.narHash')
_nix_drv=$(cat .nix_drv 2>/dev/null || echo test)
_lock_sha=$(sha256sum flake.lock | cut -d' ' -f1)
_build_date=$(date -Iseconds)
_build_host=$(hostname)
_qemu_ver=$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //')
_hw_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n') || _hw_vendor=""
_hw_product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n') || _hw_product=""
_hw_serial=$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n') || _hw_serial=""
_oci_image="${CONTAINER_REGISTRY:-registry.docker.arpa}/${CONTAINER_IMAGE:-projv-engprod/konductor}"

_tags="[\"${CONTAINER_TAG:-latest-qcow2}\""
[ "$_dirty" = "0" ] && _tags+=", \"qcow2-${_commit}\"" || _tags+=", \"qcow2-dirty\""
_tags+=", \"qcow2-${_nix_drv}\""
[ -n "$_lock_sha" ] && [ "$_lock_sha" != "unknown" ] && _tags+=", \"qcow2-${_lock_sha}\""
_tags+="]"

cat > .konductor << PROVENANCE_EOF
[konductor]
git_commit = "$_commit"
git_branch = "$_branch"
git_remote = "$_remote"
git_dirty = $_dirty
nix_version = "$_nix_ver"
nix_hash = "$_nix_hash"
nix_drv = "$_nix_drv"
flake_lock_sha256 = "$_lock_sha"
build_date = "$_build_date"
build_host = "$_build_host"
build_user = "$USER"
qemu = "$_qemu_ver"
build_hw_vendor = "$_hw_vendor"
build_hw_product = "$_hw_product"
build_hw_serial = "$_hw_serial"
strict = false
oci_image = "$_oci_image"
oci_tags = $_tags
PROVENANCE_EOF

cat .konductor
echo "PROVENANCE DONE"
```

```bash {"name":"k9:ci:test:gc","tag":"k9:ci:test,test:env"}
echo "GC: HOME=$HOME"
echo "GC: PATH=$PATH"
echo "GC: which ssh=$(which ssh 2>&1 || echo NOT_FOUND)"
```
