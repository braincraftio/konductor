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
SCP_OPTS="-P $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

cat > .konductor << PROVENANCE_EOF
[konductor]
git_commit = "$(git rev-parse HEAD)"
git_branch = "$(git rev-parse --abbrev-ref HEAD)"
git_remote = "$(git remote get-url origin 2>/dev/null || echo ORPHANED)"
git_dirty = $(git status --porcelain | wc -l | tr -d ' ')
nix_version = "$(nix --version | head -1)"
nix_hash = "$(nix flake metadata --json | jq -r '.locked.narHash')"
nix_drv = "$(cat .nix_drv 2>/dev/null || echo test)"
flake_lock_sha256 = "$(sha256sum flake.lock | cut -d' ' -f1)"
build_date = "$(date -Iseconds)"
build_host = "$(hostname)"
build_user = "${USER}"
qemu = "$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //')"
build_hw_vendor = "$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')"
build_hw_product = "$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n')"
build_hw_serial = "$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n')"
strict = false
oci_image = "registry.docker.arpa/containercraft/konductor"
oci_tags = ["latest-qcow2"]
PROVENANCE_EOF

cat .konductor

scp $SCP_OPTS .konductor kc2admin@localhost:/tmp/.konductor
ssh $SSH_OPTS kc2admin@localhost 'sudo mv /tmp/.konductor /.konductor && sudo chmod 644 /.konductor'
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
