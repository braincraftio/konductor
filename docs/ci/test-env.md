---
cwd: ../..
shell: bash
skipPrompts: true
runme:
  version: v3
---

# Test: provenance env corruption with SSH

```bash {"name":"test:before","tag":"test:env"}
echo "BEFORE: HOME=$HOME"
echo "BEFORE: PATH=$PATH"
```

```bash {"name":"test:provenance","tag":"test:env"}
set -eo pipefail
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
GIT_COMMIT=$(git rev-parse HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_REMOTE=$(git remote get-url origin 2>/dev/null) || GIT_REMOTE="ORPHANED"
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
NIX_VERSION=$(nix --version | head -1)
NIX_META=$(nix flake metadata --json)
NIX_HASH=$(echo "$NIX_META" | jq -r '.locked.narHash')
[ -n "$NIX_HASH" ] && [ "$NIX_HASH" != "null" ] || exit 1
NIX_DRV=$(cat .nix_drv 2>/dev/null) || NIX_DRV="test"
FLAKE_LOCK_SHA=$(sha256sum flake.lock | cut -d' ' -f1)
BUILD_DATE=$(date -Iseconds)
BUILD_HOST=$(hostname)
BUILD_USER="${USER:?USER not set}"
QEMU_VER=$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //')
BUILD_HW_VENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n') || BUILD_HW_VENDOR=""
BUILD_HW_PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n') || BUILD_HW_PRODUCT=""
BUILD_HW_SERIAL=$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n') || BUILD_HW_SERIAL=""
CONTAINER_IMAGE="${CONTAINER_REGISTRY:-registry.docker.arpa}/${CONTAINER_IMAGE:-containercraft/konductor}"
CONTAINER_TAGS="[\"${CONTAINER_TAG:-latest-qcow2}\""
if [ "$GIT_DIRTY" = "0" ]; then
    CONTAINER_TAGS+=", \"qcow2-${GIT_COMMIT}\""
else
    CONTAINER_TAGS+=", \"qcow2-dirty\""
fi
CONTAINER_TAGS+=", \"qcow2-${NIX_DRV}\""
CONTAINER_TAGS+="]"
KONDUCTOR_TOML="[konductor]
git_commit = \"$GIT_COMMIT\"
git_branch = \"$GIT_BRANCH\"
git_remote = \"$GIT_REMOTE\"
git_dirty = $GIT_DIRTY
nix_version = \"$NIX_VERSION\"
nix_hash = \"$NIX_HASH\"
nix_drv = \"$NIX_DRV\"
flake_lock_sha256 = \"$FLAKE_LOCK_SHA\"
build_date = \"$BUILD_DATE\"
build_host = \"$BUILD_HOST\"
build_user = \"$BUILD_USER\"
qemu = \"$QEMU_VER\"
build_hw_vendor = \"$BUILD_HW_VENDOR\"
build_hw_product = \"$BUILD_HW_PRODUCT\"
build_hw_serial = \"$BUILD_HW_SERIAL\"
strict = ${KONDUCTOR_STRICT:-false}
oci_image = \"$CONTAINER_IMAGE\"
oci_tags = $CONTAINER_TAGS"
printf '%s\n' "$KONDUCTOR_TOML" | ssh $SSH_OPTS kc2admin@localhost "sudo tee /.konductor > /dev/null"
ssh $SSH_OPTS kc2admin@localhost 'sudo chmod 644 /.konductor'
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki generate --force'
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki bundle'
ssh $SSH_OPTS kc2admin@localhost 'PYTHONPATH=/opt/konductor/src/src python3 -m pki status' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
ssh $SSH_OPTS kc2admin@localhost 'cat /.konductor' > .konductor
ssh $SSH_OPTS kc2admin@localhost 'ff' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
echo "PROVENANCE DONE"
```

```bash {"name":"test:after","tag":"test:env"}
echo "AFTER: HOME=$HOME"
echo "AFTER: PATH=$PATH"
echo "AFTER: which ssh=$(which ssh 2>&1 || echo NOT_FOUND)"
```
