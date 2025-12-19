---
cwd: ../../..
shell: bash
skipPrompts: true
runme:
  version: v3
---

# Build Konductor QCOW2

Build an airgap-ready NixOS VM image with pre-cached development environment.

**Output**: `konductor-YYYYMMDD.qcow2` (~3.5GB compressed, boots offline with full devshell)

## Quick Start

```sh {"name":"run-all","excludeFromRunAll":"true"}
runme run --filename docs/developer_guide/qcow2/BUILD.md --all
```

---

## Phase 1: Build

Nix builds the NixOS system closure into an unoptimized QCOW2.

```sh {"name":"nix-build"}
nix build .#qcow2
sudo chown -R "${USER}:${USER}" result/
sudo chmod -R u+w result/
```

## Phase 2: Prepare

Generate ephemeral build credentials and cloud-init for VM access.

```sh {"name":"cleanup"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid /tmp/konductor-build-vm.log
sudo guestunmount /tmp/nixmount 2>/dev/null || true
sudo rm -rf /tmp/nixmount /tmp/konductor-build-ssh /tmp/konductor-build-cloud-init
```

```sh {"name":"ssh-key"}
mkdir -p /tmp/konductor-build-ssh
ssh-keygen -t ed25519 -f /tmp/konductor-build-ssh/id_ed25519 -N "" -q
```

```sh {"name":"cloud-init"}
mkdir -p /tmp/konductor-build-cloud-init
BUILD_SSH_KEY=$(cat /tmp/konductor-build-ssh/id_ed25519.pub)

cat > /tmp/konductor-build-cloud-init/meta-data << 'EOF'
instance-id: konductor-build
local-hostname: konductor
EOF

cat > /tmp/konductor-build-cloud-init/user-data << EOF
#cloud-config
users:
  - name: kc2
    groups: users, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
  - name: kc2admin
    groups: users, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $BUILD_SSH_KEY
EOF

genisoimage -output /tmp/konductor-build-cloud-init/seed.iso -volid cidata -joliet -rock \
    /tmp/konductor-build-cloud-init/user-data /tmp/konductor-build-cloud-init/meta-data 2>/dev/null
```

Reset image to pristine state before first boot.

```sh {"name":"reset-image"}
export LIBGUESTFS_BACKEND=direct
sudo mkdir -p /tmp/nixmount
sudo guestmount -a result/nixos.qcow2 -m /dev/sda3 /tmp/nixmount
sudo rm -f /tmp/nixmount/etc/ssh/ssh_host_* /tmp/nixmount/etc/machine-id
sudo rm -rf /tmp/nixmount/var/lib/cloud /tmp/nixmount/var/log/journal/*
sudo guestunmount /tmp/nixmount
sync && sleep 2
```

## Phase 3: Configure

Boot VM and install development environment for airgap operation.

```sh {"name":"start-vm"}
qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -m 8192 \
    -cpu host \
    -smp "$(nproc)" \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2 \
    -drive file=/tmp/konductor-build-cloud-init/seed.iso,media=cdrom \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr \
    -daemonize \
    -pidfile /tmp/konductor-build-vm.pid \
    -serial file:/tmp/konductor-build-vm.log \
    -display none
```

```sh {"name":"wait-ssh"}
sleep 30
until .config/bin/ssh localhost true 2>/dev/null; do sleep 5; done
```

```sh {"name":"mount-workspace"}
.config/bin/ssh localhost 'sudo mkdir -p /workspace && sudo mount -t 9p -o trans=virtio host /workspace'
```

Copy source to /opt/konductor.

```sh {"name":"copy-source"}
.config/bin/ssh localhost 'sudo mkdir -p /opt/konductor && sudo rsync -a --delete \
    --exclude={result,.direnv,.env,.env.local,node_modules,__pycache__,.pytest_cache,.mypy_cache,.coverage,.devcontainer,"*.tmp","*.pyc",".DS_Store","*.qcow2","*.qcow2.tmp",.claude} \
    /workspace/ /opt/konductor/'
.config/bin/ssh localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R root:root /opt/konductor'
```

Pre-cache devshell for offline use.

```sh {"name":"cache-devshell"}
.config/bin/ssh localhost 'git config --global --add safe.directory /opt/konductor'
.config/bin/ssh localhost 'nix build /opt/konductor#devShells.x86_64-linux.konductor --out-link /home/kc2admin/konductor-devshell'
.config/bin/ssh localhost 'sudo ln -sf /home/kc2admin/konductor-devshell /nix/var/nix/gcroots/konductor-devshell'
.config/bin/ssh localhost 'nix develop /opt/konductor#konductor --command true'
```

Minimize image size.

```sh {"name":"vm-cleanup"}
.config/bin/ssh localhost 'sudo nix-collect-garbage -d'
.config/bin/ssh localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
.config/bin/ssh localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

```sh {"name":"zero-free-space"}
.config/bin/ssh localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

```sh {"name":"stop-vm"}
.config/bin/ssh localhost 'sudo poweroff' 2>/dev/null || true
sleep 10
[ -f /tmp/konductor-build-vm.pid ] && kill "$(cat /tmp/konductor-build-vm.pid)" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid
```

## Phase 4: Package

Clean build artifacts from image.

```sh {"name":"postboot-cleanup"}
export LIBGUESTFS_BACKEND=direct
sudo mkdir -p /tmp/nixmount
sudo guestmount -a result/nixos.qcow2 -m /dev/sda3 /tmp/nixmount
sudo rm -f /tmp/nixmount/etc/ssh/ssh_host_* /tmp/nixmount/etc/machine-id
sudo rm -rf /tmp/nixmount/var/lib/cloud /tmp/nixmount/var/log/journal/*
sudo rm -rf /tmp/nixmount/root/.ssh /tmp/nixmount/home/*/.ssh 2>/dev/null || true
sudo rm -f /tmp/nixmount/root/.gitconfig /tmp/nixmount/home/*/.gitconfig 2>/dev/null || true
sudo guestunmount /tmp/nixmount
sync && sleep 2
sudo rmdir /tmp/nixmount
```

Compress with ZSTD.

```sh {"name":"compress"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 "${QCOW2_OUTPUT}.tmp"
```

Sparsify for minimal size.

```sh {"name":"sparsify"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
export LIBGUESTFS_BACKEND=direct
sudo virt-sparsify --compress --convert qcow2 -o compression_type=zstd "${QCOW2_OUTPUT}.tmp" "$QCOW2_OUTPUT"
rm -f "${QCOW2_OUTPUT}.tmp"
```

```sh {"name":"final-cleanup"}
rm -rf /tmp/konductor-build-ssh /tmp/konductor-build-cloud-init /tmp/konductor-build-vm.log
```

## Phase 5: Verify

```sh {"name":"verify","interactive":"false"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
du -h "$QCOW2_OUTPUT"
qemu-img info "$QCOW2_OUTPUT"
```

---

## Container

Package as KubeVirt containerDisk for Kubernetes deployment.

```sh {"name":"build-container"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
: ${CONTAINER_IMAGE:=docker.io/containercraft/konductor:qcow2}
docker build -f Dockerfile.qcow2 --build-arg QCOW2_FILE="$QCOW2_OUTPUT" -t "$CONTAINER_IMAGE" .
```

```sh {"name":"push-container","excludeFromRunAll":"true"}
: ${CONTAINER_IMAGE:=docker.io/containercraft/konductor:qcow2}
docker push "$CONTAINER_IMAGE"
```

---

## Troubleshooting

```sh {"name":"console-log","excludeFromRunAll":"true"}
tail -100 /tmp/konductor-build-vm.log
```

```sh {"name":"kill-vm","excludeFromRunAll":"true"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid
```

```sh {"name":"ssh-vm","excludeFromRunAll":"true"}
.config/bin/ssh localhost
```
