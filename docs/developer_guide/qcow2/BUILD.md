---
cwd: ../../..
shell: bash
skipPrompts: true
tag: target:qcow2,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor QCOW2 Build

Build an airgap-ready NixOS VM image with pre-cached development environment.

## Contents

- [Output](#output)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Build Pipeline](#build-pipeline)
  - [Phase 1: Build](#phase-1-build)
  - [Phase 2: Prepare](#phase-2-prepare)
  - [Phase 3: Configure](#phase-3-configure)
  - [Phase 4: Package](#phase-4-package)
  - [Phase 5: Verify](#phase-5-verify)
- [Container Publish](#container-publish)
- [Developer Tools](#developer-tools)

---

## Output

| Artifact | Size | Description |
|----------|------|-------------|
| `konductor-YYYYMMDD.qcow2` | ~3.5GB | ZSTD-compressed QCOW2, boots offline with full devshell |
| `containercraft/konductor:qcow2` | ~3.5GB | KubeVirt containerDisk for Kubernetes deployment |

The image includes:

- NixOS with cloud-init for dynamic configuration
- Pre-cached Konductor devshell at `/opt/konductor`
- Users: `kc2` (unprivileged), `kc2admin` (sudo)
- Services: SSH, QEMU guest agent, Docker, Libvirt (not auto-started)

---

## Prerequisites

| Tool | Purpose | Tag |
|------|---------|-----|
| `nix` | Build NixOS system closure | `requires:nix` |
| `qemu-system-x86_64` | Run build VM with KVM acceleration | `requires:kvm` |
| `guestmount` / `virt-sparsify` | Mount and optimize QCOW2 images | `requires:guestfs` |
| `genisoimage` | Create cloud-init ISO | - |
| `docker` | Build containerDisk image | `requires:docker` |

---

## Quick Start

```sh {"name":"nix-build-qcow2","excludeFromRunAll":"true","tag":"type:entry"}
runme run --filename docs/developer_guide/qcow2/BUILD.md --all
```

`runme run nix-build-qcow2`

---

## Build Pipeline

```text
runme run nix-build-qcow2

phase:build  →  phase:prepare    →  phase:configure     →  phase:package     →  phase:verify
    │                │                    │                      │                   │
    ▼                ▼                    ▼                      ▼                   ▼
  -nix           -cleanup             -vm-start             -image-clean         -verify
                 -ssh-keygen          -vm-wait              -image-compress
                 -cloudinit-gen       -mount-workspace      -image-sparsify
                 -image-reset         -copy-source          -temp-cleanup
                                      -cache-warm
                                      -vm-gc
                                      -vm-zero
                                      -vm-stop

All tasks prefixed: nix-build-qcow2-{task}
```

---

## Phase 1: Build

Nix builds the NixOS system closure and creates an unoptimized QCOW2 at `result/nixos.qcow2`.

```sh {"name":"nix-build-qcow2-nix","tag":"phase:build,requires:nix"}
nix build .#qcow2
sudo chown -R "${USER}:${USER}" result/
sudo chmod -R u+w result/
```

---

## Phase 2: Prepare

Clean previous build state and generate ephemeral credentials for VM access.

```sh {"name":"nix-build-qcow2-cleanup","tag":"phase:prepare,type:destructive","excludeFromRunAll":"true"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid /tmp/konductor-build-vm.log
sudo guestunmount /tmp/nixmount 2>/dev/null || true
sudo rm -rf /tmp/nixmount /tmp/konductor-build-ssh /tmp/konductor-build-cloud-init
```

```sh {"name":"nix-build-qcow2-ssh-keygen","tag":"phase:prepare"}
mkdir -p /tmp/konductor-build-ssh
ssh-keygen -t ed25519 -f /tmp/konductor-build-ssh/id_ed25519 -N "" -q
```

```sh {"name":"nix-build-qcow2-cloudinit-gen","tag":"phase:prepare"}
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

Reset image to pristine state (remove host keys, machine-id, cloud-init state).

```sh {"name":"nix-build-qcow2-image-reset","tag":"phase:prepare,requires:guestfs"}
export LIBGUESTFS_BACKEND=direct
sudo mkdir -p /tmp/nixmount
sudo guestmount -a result/nixos.qcow2 -m /dev/sda3 /tmp/nixmount
sudo rm -f /tmp/nixmount/etc/ssh/ssh_host_* /tmp/nixmount/etc/machine-id
sudo rm -rf /tmp/nixmount/var/lib/cloud /tmp/nixmount/var/log/journal/*
sudo guestunmount /tmp/nixmount
sync && sleep 2
```

---

## Phase 3: Configure

Boot VM with virtfs mount to host workspace, then install devshell for airgap operation.

```sh {"name":"nix-build-qcow2-vm-start","tag":"phase:configure,requires:kvm"}
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

```sh {"name":"nix-build-qcow2-vm-wait","tag":"phase:configure,duration:slow"}
sleep 30
until .config/bin/ssh localhost true 2>/dev/null; do sleep 5; done
```

```sh {"name":"nix-build-qcow2-mount-workspace","tag":"phase:configure"}
.config/bin/ssh localhost 'sudo mkdir -p /workspace && sudo mount -t 9p -o trans=virtio host /workspace'
```

Copy source to `/opt/konductor` (excludes build artifacts, caches, secrets).

```sh {"name":"nix-build-qcow2-copy-source","tag":"phase:configure"}
.config/bin/ssh localhost 'sudo mkdir -p /opt/konductor && sudo rsync -a --delete \
    --exclude={result,.direnv,.env,.env.local,node_modules,__pycache__,.pytest_cache,.mypy_cache,.coverage,.devcontainer,"*.tmp","*.pyc",".DS_Store","*.qcow2","*.qcow2.tmp",.claude} \
    /workspace/ /opt/konductor/'
.config/bin/ssh localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R root:root /opt/konductor'
```

Build and cache devshell with GC root to survive garbage collection.

```sh {"name":"nix-build-qcow2-cache-warm","tag":"phase:configure,duration:slow,requires:nix"}
.config/bin/ssh localhost 'git config --global --add safe.directory /opt/konductor'
.config/bin/ssh localhost 'nix build /opt/konductor#devShells.x86_64-linux.konductor --out-link /home/kc2admin/konductor-devshell'
.config/bin/ssh localhost 'sudo ln -sf /home/kc2admin/konductor-devshell /nix/var/nix/gcroots/konductor-devshell'
.config/bin/ssh localhost 'nix develop /opt/konductor#konductor --command true'
```

Minimize image size (garbage collect, clear logs/caches, zero free space for compression).

```sh {"name":"nix-build-qcow2-vm-gc","tag":"phase:configure"}
.config/bin/ssh localhost 'sudo nix-collect-garbage -d'
.config/bin/ssh localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
.config/bin/ssh localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

```sh {"name":"nix-build-qcow2-vm-zero","tag":"phase:configure,duration:slow"}
.config/bin/ssh localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

```sh {"name":"nix-build-qcow2-vm-stop","tag":"phase:configure"}
.config/bin/ssh localhost 'sudo poweroff' 2>/dev/null || true
sleep 10
[ -f /tmp/konductor-build-vm.pid ] && kill "$(cat /tmp/konductor-build-vm.pid)" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid
```

---

## Phase 4: Package

Clean build artifacts (SSH keys, gitconfig) from the image.

```sh {"name":"nix-build-qcow2-image-clean","tag":"phase:package,requires:guestfs"}
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

Compress with ZSTD (best ratio for QCOW2).

```sh {"name":"nix-build-qcow2-image-compress","tag":"phase:package,duration:slow"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 "${QCOW2_OUTPUT}.tmp"
```

Sparsify to reclaim zero-filled space.

```sh {"name":"nix-build-qcow2-image-sparsify","tag":"phase:package,duration:slow,requires:guestfs"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
export LIBGUESTFS_BACKEND=direct
sudo virt-sparsify --compress --convert qcow2 -o compression_type=zstd "${QCOW2_OUTPUT}.tmp" "$QCOW2_OUTPUT"
rm -f "${QCOW2_OUTPUT}.tmp"
```

```sh {"name":"nix-build-qcow2-temp-cleanup","tag":"phase:package"}
rm -rf /tmp/konductor-build-ssh /tmp/konductor-build-cloud-init /tmp/konductor-build-vm.log
```

---

## Phase 5: Verify

```sh {"name":"nix-build-qcow2-verify","tag":"phase:verify,type:readonly","interactive":"false"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
echo "=== QCOW2 Build Complete ==="
du -h "$QCOW2_OUTPUT"
qemu-img info "$QCOW2_OUTPUT"
```

---

## Container Publish

Package QCOW2 as a KubeVirt containerDisk for Kubernetes deployment.

```sh {"name":"nix-build-qcow2-container-build","tag":"phase:publish,requires:docker","excludeFromRunAll":"true"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
: ${CONTAINER_IMAGE:=docker.io/containercraft/konductor:qcow2}
docker build -f Dockerfile.qcow2 --build-arg QCOW2_FILE="$QCOW2_OUTPUT" -t "$CONTAINER_IMAGE" .
```

```sh {"name":"nix-build-qcow2-container-push","tag":"phase:publish,requires:docker","excludeFromRunAll":"true"}
: ${CONTAINER_IMAGE:=docker.io/containercraft/konductor:qcow2}
docker push "$CONTAINER_IMAGE"
```

---

## Developer Tools

Debug and troubleshooting utilities (excluded from `--all`).

**View boot log:**

```sh {"name":"nix-build-qcow2-debug-log","tag":"type:debug","excludeFromRunAll":"true"}
tail -100 /tmp/konductor-build-vm.log
```

**Force kill stuck VM:**

```sh {"name":"nix-build-qcow2-vm-kill","tag":"type:destructive","excludeFromRunAll":"true"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid
```

**SSH into running VM:**

```sh {"name":"nix-build-qcow2-vm-ssh","tag":"type:debug","excludeFromRunAll":"true"}
.config/bin/ssh localhost
```
