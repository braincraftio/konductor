---
cwd: ../../..
shell: bash
skipPrompts: true
runme:
  version: v3
---

# Konductor QCOW2 Build Guide

Build an optimized, airgap-ready NixOS QCOW2 image with pre-cached devshell.

## Overview

This guide produces:
- Compressed QCOW2 disk image (~3.5GB)
- KubeVirt-compatible containerDisk image
- Airgap-ready with `/opt/konductor` source and cached devshell

## Prerequisites

```sh {"name":"check-prereqs","interactive":"false"}
echo "Checking prerequisites..."
command -v nix >/dev/null && echo "nix: OK" || echo "nix: MISSING"
command -v qemu-system-x86_64 >/dev/null && echo "qemu: OK" || echo "qemu: MISSING"
command -v guestmount >/dev/null && echo "libguestfs: OK" || echo "libguestfs: MISSING"
command -v virt-sparsify >/dev/null && echo "virt-sparsify: OK" || echo "virt-sparsify: MISSING"
command -v genisoimage >/dev/null && echo "genisoimage: OK" || echo "genisoimage: MISSING"
command -v docker >/dev/null && echo "docker: OK" || echo "docker: MISSING"
command -v ssh-keygen >/dev/null && echo "ssh-keygen: OK" || echo "ssh-keygen: MISSING"
```

## Environment

Variables are loaded from `.env` (see `.env.example` for documentation).

```sh {"name":"show-env","interactive":"false"}
# Show current build configuration
: ${LIBGUESTFS_BACKEND:=direct}
: ${QCOW2_MOUNT:=/tmp/nixmount}
: ${QCOW2_CLOUD_INIT_DIR:=/tmp/konductor-build-cloud-init}
: ${QCOW2_PIDFILE:=/tmp/konductor-build-vm.pid}
: ${QCOW2_SSH_KEY_DIR:=/tmp/konductor-build-ssh}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}
: ${QCOW2_VM_MEMORY:=8192}
: ${QCOW2_SSH_PORT:=2222}
: ${QCOW2_SSH_TIMEOUT:=300}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}

echo "LIBGUESTFS_BACKEND=$LIBGUESTFS_BACKEND"
echo "QCOW2_OUTPUT=$QCOW2_OUTPUT"
echo "QCOW2_MOUNT=$QCOW2_MOUNT"
echo "QCOW2_SSH_PORT=$QCOW2_SSH_PORT"
echo "QCOW2_VM_MEMORY=$QCOW2_VM_MEMORY"
```

## Cleanup

### Cleanup Stale Processes

```sh {"name":"cleanup-processes"}
: ${QCOW2_PIDFILE:=/tmp/konductor-build-vm.pid}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}

echo "=== Cleanup Stale Processes ==="
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
if [ -f "$QCOW2_PIDFILE" ]; then
    kill "$(cat "$QCOW2_PIDFILE")" 2>/dev/null || true
    rm -f "$QCOW2_PIDFILE"
fi
rm -f "$QCOW2_LOGFILE"
sleep 2
echo "Process cleanup complete"
```

### Cleanup Stale Mounts

```sh {"name":"cleanup-mounts"}
: ${QCOW2_MOUNT:=/tmp/nixmount}

echo "=== Cleanup Stale Mounts ==="
sudo guestunmount "$QCOW2_MOUNT" 2>/dev/null || true
sudo umount "$QCOW2_MOUNT" 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"
echo "Mount cleanup complete"
```

## Build Phase

### Generate Build SSH Key

```sh {"name":"generate-ssh-key"}
: ${QCOW2_SSH_KEY_DIR:=/tmp/konductor-build-ssh}

echo "=== Generating Build SSH Key ==="
rm -rf "$QCOW2_SSH_KEY_DIR"
mkdir -p "$QCOW2_SSH_KEY_DIR"
ssh-keygen -t ed25519 -f "$QCOW2_SSH_KEY_DIR/id_ed25519" -N "" -q
echo "SSH key generated: $QCOW2_SSH_KEY_DIR/id_ed25519"
cat "$QCOW2_SSH_KEY_DIR/id_ed25519.pub"
```

### Build QCOW2 with Nix

```sh {"name":"nix-build"}
echo "=== Building QCOW2 ==="
nix build .#qcow2
sudo chown -R "${USER}:${USER}" result/
sudo chmod -R u+w result/
echo "Nix build complete: result/nixos.qcow2"
ls -lh result/nixos.qcow2
```

### Create Cloud-Init ISO

```sh {"name":"create-cloud-init"}
: ${QCOW2_SSH_KEY_DIR:=/tmp/konductor-build-ssh}
: ${QCOW2_CLOUD_INIT_DIR:=/tmp/konductor-build-cloud-init}

echo "=== Creating Build Cloud-Init ==="
rm -rf "$QCOW2_CLOUD_INIT_DIR"
mkdir -p "$QCOW2_CLOUD_INIT_DIR"

# Read the SSH public key
BUILD_SSH_KEY=$(cat "$QCOW2_SSH_KEY_DIR/id_ed25519.pub")

cat > "$QCOW2_CLOUD_INIT_DIR/meta-data" << 'META_EOF'
instance-id: konductor-build
local-hostname: konductor
META_EOF

cat > "$QCOW2_CLOUD_INIT_DIR/user-data" << USER_EOF
#cloud-config
users:
  - name: kc2
    gecos: Konductor Unprivileged User
    groups: users, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
  - name: kc2admin
    gecos: Konductor Admin User
    groups: users, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

write_files:
  - path: /etc/sudoers.d/kc2-power
    content: |
      kc2 ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/poweroff, /run/current-system/sw/bin/reboot, /run/current-system/sw/bin/shutdown
    permissions: '0440'
  - path: /home/kc2admin/.ssh/authorized_keys
    content: |
      $BUILD_SSH_KEY
    permissions: '0600'
    owner: kc2admin:users

runcmd:
  - chmod 700 /home/kc2admin/.ssh
USER_EOF

genisoimage -output "$QCOW2_CLOUD_INIT_DIR/seed.iso" -volid cidata -joliet -rock \
    "$QCOW2_CLOUD_INIT_DIR/user-data" "$QCOW2_CLOUD_INIT_DIR/meta-data" 2>/dev/null

echo "Cloud-init ISO created: $QCOW2_CLOUD_INIT_DIR/seed.iso"
```

### Pre-boot Guestmount Cleanup

```sh {"name":"preboot-cleanup"}
: ${LIBGUESTFS_BACKEND:=direct}
: ${QCOW2_MOUNT:=/tmp/nixmount}
export LIBGUESTFS_BACKEND

echo "=== Pre-boot Guestmount Cleanup ==="
sudo rm -rf "$QCOW2_MOUNT"
sudo mkdir -p "$QCOW2_MOUNT"
sudo guestmount -a result/nixos.qcow2 -m /dev/sda3 "$QCOW2_MOUNT"

# Cleanup sensitive/stale data
sudo rm -f "$QCOW2_MOUNT"/etc/ssh/ssh_host_*
sudo rm -f "$QCOW2_MOUNT"/etc/machine-id
sudo rm -f "$QCOW2_MOUNT"/root/.bash_history
sudo rm -f "$QCOW2_MOUNT"/home/*/.bash_history 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/var/lib/cloud
sudo rm -rf "$QCOW2_MOUNT"/var/log/journal/*
sudo rm -rf "$QCOW2_MOUNT"/tmp/* 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/var/tmp/* 2>/dev/null || true

# Verify cloud-init state removed
if sudo ls -la "$QCOW2_MOUNT/var/lib/" | grep -qE "cloud|Cloud"; then
    echo "ERROR: cloud-init state still exists"
    sudo guestunmount "$QCOW2_MOUNT"
    exit 1
fi
echo "Verified: /var/lib/cloud removed"

sudo guestunmount "$QCOW2_MOUNT"
sync
sleep 2
echo "Pre-boot cleanup complete"
```

## VM Phase

### Start VM

```sh {"name":"start-vm"}
: ${QCOW2_CLOUD_INIT_DIR:=/tmp/konductor-build-cloud-init}
: ${QCOW2_PIDFILE:=/tmp/konductor-build-vm.pid}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}
: ${QCOW2_VM_MEMORY:=8192}
: ${QCOW2_SSH_PORT:=2222}

echo "=== Starting VM ==="
echo "Console log: $QCOW2_LOGFILE"
qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -m "$QCOW2_VM_MEMORY" \
    -cpu host \
    -smp "$(nproc)" \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2 \
    -drive file="$QCOW2_CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,hostfwd=tcp::${QCOW2_SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr \
    -daemonize \
    -pidfile "$QCOW2_PIDFILE" \
    -serial file:"$QCOW2_LOGFILE" \
    -display none

echo "VM started (PID: $(cat $QCOW2_PIDFILE))"
```

### Wait for SSH

```sh {"name":"wait-ssh"}
: ${QCOW2_SSH_TIMEOUT:=300}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}

echo "=== Waiting for SSH ==="
sleep 30  # Give cloud-init time to run
SSH_ELAPSED=0
until .config/bin/ssh localhost true 2>/dev/null; do
    sleep 5
    SSH_ELAPSED=$((SSH_ELAPSED + 5))
    echo "Waiting... ${SSH_ELAPSED}s / ${QCOW2_SSH_TIMEOUT}s"
    if [ $SSH_ELAPSED -ge $QCOW2_SSH_TIMEOUT ]; then
        echo "ERROR: SSH timeout after ${QCOW2_SSH_TIMEOUT}s. Check $QCOW2_LOGFILE"
        tail -50 "$QCOW2_LOGFILE"
        exit 1
    fi
done
echo "SSH ready"
```

### Mount Workspace in VM

```sh {"name":"mount-workspace"}
echo "=== Mounting Workspace ==="
.config/bin/ssh localhost 'sudo mkdir -p /workspace && sudo mount -t 9p -o trans=virtio host /workspace'
.config/bin/ssh localhost 'ls /workspace/flake.nix' || { echo "ERROR: Workspace mount failed"; exit 1; }
echo "Workspace mounted"
```

### Copy Source to /opt/konductor

```sh {"name":"copy-source"}
echo "=== Copy Source to /opt/konductor ==="
.config/bin/ssh localhost 'sudo mkdir -p /opt/konductor'
.config/bin/ssh localhost 'sudo rsync -a --delete \
    --exclude=result \
    --exclude=.direnv \
    --exclude=.env \
    --exclude=.env.local \
    --exclude=node_modules \
    --exclude=__pycache__ \
    --exclude=.pytest_cache \
    --exclude=.mypy_cache \
    --exclude=.coverage \
    --exclude=.devcontainer \
    --exclude="*.tmp" \
    --exclude="*.pyc" \
    --exclude=".DS_Store" \
    --exclude="*.qcow2" \
    --exclude="*.qcow2.tmp" \
    --exclude="build-report.log" \
    --exclude="tmp.tmp" \
    /workspace/ /opt/konductor/'

# Clean up build artifacts
.config/bin/ssh localhost 'sudo rm -rf /opt/konductor/*.qcow2* /opt/konductor/build-report.log /opt/konductor/tmp.tmp /opt/konductor/.claude 2>/dev/null || true'
.config/bin/ssh localhost 'sudo chmod -R a+rX /opt/konductor'
.config/bin/ssh localhost 'sudo chown -R root:root /opt/konductor'

# Verify
.config/bin/ssh localhost 'ls /opt/konductor/flake.nix /opt/konductor/.git/HEAD' || { echo "ERROR: /opt/konductor copy incomplete"; exit 1; }
echo "Source copied to /opt/konductor"
```

### Pre-cache Devshell (Airgap)

```sh {"name":"cache-devshell"}
echo "=== Pre-cache Devshell (airgap ready) ==="
.config/bin/ssh localhost 'git config --global --add safe.directory /opt/konductor'

# Build devshell and create GC root to prevent garbage collection
.config/bin/ssh localhost 'nix build /opt/konductor#devShells.x86_64-linux.konductor --out-link /home/kc2admin/konductor-devshell'
.config/bin/ssh localhost 'sudo ln -sf /home/kc2admin/konductor-devshell /nix/var/nix/gcroots/konductor-devshell'

# Warm the cache by entering the shell
.config/bin/ssh localhost 'nix develop /opt/konductor#konductor --command true'
echo "Devshell cached with GC root"
```

### Nix Garbage Collection

```sh {"name":"nix-gc"}
echo "=== Nix Garbage Collection (after devshell cache) ==="
.config/bin/ssh localhost 'sudo nix-collect-garbage -d'
echo "Garbage collection complete"
```

### Journal and Log Cleanup

```sh {"name":"cleanup-logs"}
echo "=== Journal and Log Cleanup ==="
.config/bin/ssh localhost 'sudo journalctl --vacuum-size=1M'
.config/bin/ssh localhost 'sudo rm -rf /var/log/journal/*'
.config/bin/ssh localhost 'sudo rm -rf /nix/var/log/nix/drvs/*'
.config/bin/ssh localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
echo "Log cleanup complete"
```

### Zero Free Space

```sh {"name":"zero-free-space"}
echo "=== Zeroing Free Space ==="
.config/bin/ssh localhost 'sudo dd if=/dev/zero of=/zero bs=1M status=progress 2>&1 || true'
.config/bin/ssh localhost 'sudo rm -f /zero && sync'
echo "Free space zeroed (enables compression)"
```

### Stop VM

```sh {"name":"stop-vm"}
: ${QCOW2_PIDFILE:=/tmp/konductor-build-vm.pid}

echo "=== Stopping VM ==="
.config/bin/ssh localhost 'sudo poweroff' 2>/dev/null || true
sleep 10

# Force kill if still running
if [ -f "$QCOW2_PIDFILE" ]; then
    kill "$(cat "$QCOW2_PIDFILE")" 2>/dev/null || true
    rm -f "$QCOW2_PIDFILE"
fi
sleep 2
echo "VM stopped"
```

## Post-Processing

### Post-boot Guestmount Cleanup

```sh {"name":"postboot-cleanup"}
: ${LIBGUESTFS_BACKEND:=direct}
: ${QCOW2_MOUNT:=/tmp/nixmount}
export LIBGUESTFS_BACKEND

echo "=== Post-boot Guestmount Cleanup ==="
sudo rm -rf "$QCOW2_MOUNT"
sudo mkdir -p "$QCOW2_MOUNT"
sudo guestmount -a result/nixos.qcow2 -m /dev/sda3 "$QCOW2_MOUNT"

# Base cleanup
sudo rm -f "$QCOW2_MOUNT"/etc/ssh/ssh_host_*
sudo rm -f "$QCOW2_MOUNT"/etc/machine-id
sudo rm -f "$QCOW2_MOUNT"/root/.bash_history
sudo rm -f "$QCOW2_MOUNT"/home/*/.bash_history 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/var/lib/cloud
sudo rm -rf "$QCOW2_MOUNT"/var/log/journal/*
sudo rm -rf "$QCOW2_MOUNT"/tmp/* 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/var/tmp/* 2>/dev/null || true

# Build process artifacts
sudo rm -rf "$QCOW2_MOUNT"/root/.ssh 2>/dev/null || true
sudo rm -f "$QCOW2_MOUNT"/root/.gitconfig 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/home/*/.ssh 2>/dev/null || true
sudo rm -f "$QCOW2_MOUNT"/home/*/.gitconfig 2>/dev/null || true
sudo rm -rf "$QCOW2_MOUNT"/var/log/*.log 2>/dev/null || true

sudo guestunmount "$QCOW2_MOUNT"
sync
sleep 2
sudo rmdir "$QCOW2_MOUNT"
echo "Post-boot cleanup complete"
```

### Compress with ZSTD

```sh {"name":"compress-zstd"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}

echo "=== Compressing with ZSTD ==="
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 "${QCOW2_OUTPUT}.tmp"
echo "ZSTD compression complete"
ls -lh "${QCOW2_OUTPUT}.tmp"
```

### Sparsify

```sh {"name":"sparsify"}
: ${LIBGUESTFS_BACKEND:=direct}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
export LIBGUESTFS_BACKEND

echo "=== Sparsifying ==="
sudo virt-sparsify --compress --convert qcow2 -o compression_type=zstd "${QCOW2_OUTPUT}.tmp" "$QCOW2_OUTPUT"
rm -f "${QCOW2_OUTPUT}.tmp"
echo "Sparsification complete"
```

### Final Cleanup

```sh {"name":"final-cleanup"}
: ${QCOW2_SSH_KEY_DIR:=/tmp/konductor-build-ssh}
: ${QCOW2_CLOUD_INIT_DIR:=/tmp/konductor-build-cloud-init}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}

echo "=== Cleanup ==="
rm -rf "$QCOW2_SSH_KEY_DIR"
rm -rf "$QCOW2_CLOUD_INIT_DIR"
rm -f "$QCOW2_LOGFILE"
echo "Build artifacts cleaned"
```

### Verify QCOW2

```sh {"name":"verify-qcow2","interactive":"false"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}

echo "=== QCOW2 Complete ==="
du -h "$QCOW2_OUTPUT"
qemu-img info "$QCOW2_OUTPUT"
```

## Container Image

### Build ContainerDisk

```sh {"name":"build-container"}
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
: ${CONTAINER_REGISTRY:=docker.io}
: ${CONTAINER_IMAGE:=containercraft/konductor}
: ${CONTAINER_TAG:=qcow2}

FULL_IMAGE="${CONTAINER_REGISTRY}/${CONTAINER_IMAGE}:${CONTAINER_TAG}"

echo "=== Building Container Image ==="
docker build -f Dockerfile.qcow2 --build-arg QCOW2_FILE="$QCOW2_OUTPUT" -t "$FULL_IMAGE" .
echo "Container image built: $FULL_IMAGE"
```

### Verify Container

```sh {"name":"verify-container","interactive":"false"}
: ${CONTAINER_REGISTRY:=docker.io}
: ${CONTAINER_IMAGE:=containercraft/konductor}
: ${CONTAINER_TAG:=qcow2}

FULL_IMAGE="${CONTAINER_REGISTRY}/${CONTAINER_IMAGE}:${CONTAINER_TAG}"

echo "=== Container Image ==="
docker images "$FULL_IMAGE"
```

### Push Container

```sh {"name":"push-container","excludeFromRunAll":"true"}
: ${CONTAINER_REGISTRY:=docker.io}
: ${CONTAINER_IMAGE:=containercraft/konductor}
: ${CONTAINER_TAG:=qcow2}

FULL_IMAGE="${CONTAINER_REGISTRY}/${CONTAINER_IMAGE}:${CONTAINER_TAG}"

echo "=== Pushing Container Image ==="
docker push "$FULL_IMAGE"
```

## Troubleshooting

### View VM Console Log

```sh {"name":"view-console-log","excludeFromRunAll":"true"}
: ${QCOW2_LOGFILE:=/tmp/konductor-build-vm.log}
tail -100 "$QCOW2_LOGFILE"
```

### Force Kill VM

```sh {"name":"force-kill-vm","excludeFromRunAll":"true"}
: ${QCOW2_PIDFILE:=/tmp/konductor-build-vm.pid}

pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "$QCOW2_PIDFILE"
echo "VM killed"
```

### SSH into Running VM

```sh {"name":"ssh-vm","excludeFromRunAll":"true"}
.config/bin/ssh localhost
```

### Check libguestfs

```sh {"name":"check-libguestfs","excludeFromRunAll":"true","interactive":"false"}
: ${LIBGUESTFS_BACKEND:=direct}
export LIBGUESTFS_BACKEND

libguestfs-test-tool 2>&1 | tail -20
```

### Diagnostic: Source Size

```sh {"name":"diag-source-size","excludeFromRunAll":"true","interactive":"false"}
echo "=== Diagnostic: /opt/konductor size ==="
.config/bin/ssh localhost 'du -sh /opt/konductor/ && du -sh /opt/konductor/*/'
```

### Diagnostic: Disk Usage

```sh {"name":"diag-disk-usage","excludeFromRunAll":"true","interactive":"false"}
echo "=== Diagnostic: Disk and nix store usage ==="
.config/bin/ssh localhost 'df -h /'
.config/bin/ssh localhost 'du -sh /nix/store/*/' | sort -rh | head -20
```
