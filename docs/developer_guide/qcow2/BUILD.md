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
- [Task Reference](#task-reference)
- [Pipeline Tasks](#pipeline-tasks)
- [Debug Tools](#debug-tools)

---

## Output

| Artifact | Size | Description |
|----------|------|-------------|
| `konductor-YYYYMMDD.qcow2` | ~4GB | ZSTD-compressed QCOW2, boots offline with full toolchain |
| `docker.io/containercraft/konductor:latest-qcow2` | ~4GB | KubeVirt containerDisk (also on ghcr.io/braincraftio/konductor) |

The image includes:

- NixOS with cloud-init for dynamic configuration
- **Full Konductor environment pre-installed** - no `nix develop` needed
- All languages: Python, Go, Node.js, Rust
- IDE: Neovim (fully configured), tmux
- Self-hosting: Docker, QEMU, libvirt, Buildkit
- Linters, formatters, AI tools
- Users: `kc2` (unprivileged), `kc2admin` (sudo), `runner` (CI/CD)
- Services: SSH, QEMU guest agent, Docker, Libvirt (not auto-started)

---

## Prerequisites

All prerequisites are provided by `nix develop` (devshell).

| Tool | Purpose | Tag |
|------|---------|-----|
| `nix` | Build NixOS system closure | `requires:nix` |
| `qemu-system-x86_64` | Run build VM with KVM acceleration | `requires:kvm` |
| `OVMF` | EFI firmware (env: `$OVMF_CODE`, `$OVMF_VARS`) | `requires:efi` |
| `guestfs-tools` | Mount and optimize QCOW2 images | `requires:guestfs` |
| `genisoimage` | Create cloud-init ISO | - |
| `docker` | Build containerDisk image (optional) | `requires:docker` |
| SSH config | `ssh localhost` → port 2222 (auto-configured by devshell) | - |

---

## Quick Start

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  build:qcow2                    Show this help                              │
│    ├── :clean                   Reset build state                           │
│    ├── :image                   Build QCOW2 (nix → VM configure → package)  │
│    ├── :container               Package QCOW2 as containerDisk              │
│    ├── :login                   Authenticate to registry                    │
│    ├── :push                    Push container to registry                  │
│    ├── :start                   Boot image for local development            │
│    ├── :ssh                     SSH into running VM                         │
│    ├── :stop                    Graceful VM shutdown                        │
│    └── :publish                 Full automation: image → container → push   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### build:qcow2

Show available tasks.

```sh {"name":"build:qcow2","excludeFromRunAll":"true","tag":"type:entry"}
cat << 'EOF'
build:qcow2 - Konductor QCOW2 Build Tasks

Usage: runme run build:qcow2:<task>

Tasks:
  :clean      Reset build state
  :image      Build QCOW2 (nix → VM configure → compress → verify)
  :container  Package QCOW2 as containerDisk
  :login      Authenticate to registry
  :push       Push container to registry
  :start      Boot image for local development
  :ssh        SSH into running VM
  :stop       Graceful VM shutdown
  :publish    Full automation: image → container → login → push

Examples:
  runme run build:qcow2:publish                  # From zero to published
  runme run build:qcow2:image                    # Build QCOW2 only
  runme run build:qcow2:start && ssh localhost   # Local development

Output:
  konductor-YYYYMMDD.qcow2                         # ZSTD-compressed QCOW2
  docker.io/containercraft/konductor:latest-qcow2  # KubeVirt containerDisk
EOF
```

`runme run build:qcow2`

---

### build:qcow2:clean

Reset build state. Kills running VM, removes temp files.

```sh {"name":"build:qcow2:clean","excludeFromRunAll":"true","tag":"type:entry,type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid /tmp/konductor-build-vm.log
sudo guestunmount /tmp/nixmount 2>/dev/null || true
sudo rm -rf /tmp/nixmount /tmp/konductor-build-cloud-init
rm -rf result result.writable 2>/dev/null || true
```

`runme run build:qcow2:clean`

---

### build:qcow2:image

Build QCOW2: nix build → VM configure → compress → sparsify → verify.

```text
build:qcow2:image

  stop → clean → nix → cloudinit → img:reset → vm:boot → vm:wait → vm:sync
    │       │      │        │           │           │         │         │
    ▼       ▼      ▼        ▼           ▼           ▼         ▼         ▼
 graceful force  build  generate    reset VM    boot VM   wait for   rsync to
 shutdown clean  QCOW2  cloud-init  to pristine           SSH ready  /opt/konductor

  → vm:gc → vm:zero → vm:halt → img:clean → img:compress → img:sparsify → verify
       │        │          │          │            │              │           │
       ▼        ▼          ▼          ▼            ▼              ▼           ▼
    garbage   zero     shutdown   clean SSH     ZSTD          reclaim      show
    collect   free     VM         keys/git     compress       sparse       size
```

```sh {"name":"build:qcow2:image","excludeFromRunAll":"true","tag":"type:entry"}
set -e
runme run build:qcow2:stop
runme run build:qcow2:clean
runme run --filename docs/developer_guide/qcow2/BUILD.md --all
```

`runme run build:qcow2:image`

---

### build:qcow2:container

Package QCOW2 as containerDisk for KubeVirt.

```sh {"name":"build:qcow2:container","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
# Variables from _build:qcow2:env or defaults for standalone run
: ${QCOW2_OUTPUT:=konductor-$(date +%Y%m%d).qcow2}
: ${FULL_IMAGE:=${CONTAINER_REGISTRY:-docker.io}/${CONTAINER_IMAGE:-containercraft/konductor}:${CONTAINER_TAG:-latest-qcow2}}

[ -f "$QCOW2_OUTPUT" ] || { echo "Error: $QCOW2_OUTPUT not found. Run build:qcow2:image first."; exit 1; }
[ -f Dockerfile.qcow2 ] || { echo "Error: Dockerfile.qcow2 not found"; exit 1; }

echo "Building containerDisk from: $QCOW2_OUTPUT"
echo "Target image: $FULL_IMAGE"
# --provenance=false --sbom=false: disable attestations for clean OCI images
docker buildx build -f Dockerfile.qcow2 --build-arg QCOW2_FILE="$QCOW2_OUTPUT" \
    --provenance=false \
    --sbom=false \
    --load -t "$FULL_IMAGE" .
echo ""
echo "Built: $FULL_IMAGE"
docker images "$FULL_IMAGE" --format "Size: {{.Size}}"
```

`runme run build:qcow2:container`

---

### build:qcow2:login

Authenticate to container registry. Supports Docker Hub and GHCR.

Logic:
1. If token provided (DOCKER_TOKEN or GITHUB_TOKEN) → login with token
2. If already authenticated (docker config) → skip
3. Otherwise → error with instructions

```sh {"name":"build:qcow2:login","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
: ${CONTAINER_REGISTRY:=docker.io}

# Normalize registry name for config lookup
if [[ "$CONTAINER_REGISTRY" == "docker.io" ]]; then
  CONFIG_REGISTRY="https://index.docker.io/v1/"
else
  CONFIG_REGISTRY="$CONTAINER_REGISTRY"
fi

# Docker Hub authentication
if [[ "$CONTAINER_REGISTRY" == "docker.io" ]]; then
  # If token provided, always login (CI path - token injected as secret)
  if [[ -n "$DOCKER_TOKEN" ]]; then
    echo "$DOCKER_TOKEN" | docker login docker.io -u "${DOCKER_USERNAME:-containercraft}" --password-stdin
    echo "Logged in to Docker Hub as ${DOCKER_USERNAME:-containercraft}"
    exit 0
  fi
  # Check if already logged in via docker config
  if grep -q "$CONFIG_REGISTRY" ~/.docker/config.json 2>/dev/null; then
    echo "Already authenticated to Docker Hub (found in docker config)"
    exit 0
  fi
  # Not authenticated
  echo "Not authenticated to Docker Hub."
  echo ""
  echo "Options:"
  echo "  1. Run: docker login"
  echo "  2. Set DOCKER_TOKEN in .env (DOCKER_USERNAME defaults to containercraft)"
  echo "  3. Export DOCKER_TOKEN in environment"
  exit 1

# GHCR authentication
elif [[ "$CONTAINER_REGISTRY" == "ghcr.io" ]]; then
  # If token provided, always login (CI path)
  if [[ -n "$GITHUB_TOKEN" ]]; then
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-github}" --password-stdin
    echo "Logged in to GHCR as ${GITHUB_ACTOR:-github}"
    exit 0
  fi
  # Check if already logged in via docker config
  if grep -q "$CONFIG_REGISTRY" ~/.docker/config.json 2>/dev/null; then
    echo "Already authenticated to GHCR (found in docker config)"
    exit 0
  fi
  # Not authenticated
  echo "Not authenticated to GHCR."
  echo ""
  echo "Options:"
  echo "  1. Run: docker login ghcr.io"
  echo "  2. Set GITHUB_TOKEN in .env (GITHUB_ACTOR defaults to github)"
  echo "  3. Export GITHUB_TOKEN in environment"
  exit 1

else
  # Custom registry - check if already authenticated
  if grep -q "$CONTAINER_REGISTRY" ~/.docker/config.json 2>/dev/null; then
    echo "Already authenticated to $CONTAINER_REGISTRY (found in docker config)"
    exit 0
  fi
  # Login with custom creds or default admin:admin
  : ${REGISTRY_USERNAME:=admin}
  : ${REGISTRY_PASSWORD:=admin}
  echo "$REGISTRY_PASSWORD" | docker login "$CONTAINER_REGISTRY" -u "$REGISTRY_USERNAME" --password-stdin
  echo "Logged in to $CONTAINER_REGISTRY as $REGISTRY_USERNAME"
fi
```

`runme run build:qcow2:login`

---

### build:qcow2:push

Push container to registry as OCI image.

```sh {"name":"build:qcow2:push","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
# Variables from _build:qcow2:env or defaults for standalone run
: ${FULL_IMAGE:=${CONTAINER_REGISTRY:-docker.io}/${CONTAINER_IMAGE:-containercraft/konductor}:${CONTAINER_TAG:-latest-qcow2}}

# Verify image exists in local docker daemon (built by build:qcow2:container)
docker image inspect "$FULL_IMAGE" &>/dev/null || { echo "Error: $FULL_IMAGE not found. Run build:qcow2:container first."; exit 1; }

echo "Pushing: $FULL_IMAGE"
# Use skopeo for reliable OCI push (docker buildx has manifest issues with some registries)
skopeo copy --dest-tls-verify=false \
    docker-daemon:"$FULL_IMAGE" \
    docker://"$FULL_IMAGE"

echo ""
echo "=== Push Complete ==="
echo "Image: $FULL_IMAGE"

# Validate image in registry
echo ""
echo "=== Validating ==="
skopeo inspect --tls-verify=false docker://"$FULL_IMAGE" | jq '{Digest, Created, Architecture, Os}'
```

`runme run build:qcow2:push`

---

### build:qcow2:start

Boot image for local development. Auto-builds if missing.

```text
build:qcow2:start

  [check running] → [check image] → clean → cloudinit → vm:boot → vm:wait
         │                │           │          │           │         │
         ▼                ▼           ▼          ▼           ▼         ▼
   if running:      if missing:    force     generate     boot VM   wait for
   exit early       run build      cleanup   cloud-init   with EFI  SSH ready
```

```sh {"name":"build:qcow2:start","excludeFromRunAll":"true","tag":"type:entry"}
set -e
if [ -f /tmp/konductor-build-vm.pid ] && kill -0 "$(cat /tmp/konductor-build-vm.pid)" 2>/dev/null; then
    echo "VM already running. Use: ssh localhost"
    exit 0
fi
if [ ! -f result/nixos.qcow2 ]; then
    echo "No image found. Building..."
    runme run build:qcow2:image
fi
runme run build:qcow2:clean
runme run _build:qcow2:cloudinit
runme run _build:qcow2:vm:boot
runme run _build:qcow2:vm:wait
echo ""
echo "VM ready! Run: ssh localhost"
```

`runme run build:qcow2:start && ssh localhost`

---

### build:qcow2:ssh

SSH into running VM.

```sh {"name":"build:qcow2:ssh","excludeFromRunAll":"true","tag":"type:entry"}
ssh localhost
```

`runme run build:qcow2:ssh`

---

### build:qcow2:stop

Graceful VM shutdown.

```sh {"name":"build:qcow2:stop","excludeFromRunAll":"true","tag":"type:entry"}
set -e
runme run _build:qcow2:vm:halt
echo "VM stopped"
```

`runme run build:qcow2:stop`

---

### build:qcow2:publish

Full automation: clean → image → container → login → push.

```text
build:qcow2:publish

  :clean → :image → :container → :login → :push
     │        │          │          │        │
     ▼        ▼          ▼          ▼        ▼
   reset    build     package    registry  skopeo
   state    QCOW2     container   auth     push
```

```sh {"name":"build:qcow2:publish","excludeFromRunAll":"true","tag":"type:entry"}
set -e
# Variables from _build:qcow2:env or defaults for standalone run
: ${FULL_IMAGE:=${CONTAINER_REGISTRY:-docker.io}/${CONTAINER_IMAGE:-containercraft/konductor}:${CONTAINER_TAG:-latest-qcow2}}

echo "=== Publishing: $FULL_IMAGE ==="
echo ""
runme run build:qcow2:clean
runme run build:qcow2:image
runme run build:qcow2:container
runme run build:qcow2:login
runme run build:qcow2:push
echo ""
echo "=== Publish Complete ==="
echo "Image: $FULL_IMAGE"
```

`runme run build:qcow2:publish`

---

## Task Reference

```text
Entry Points (user-facing):
  build:qcow2              Show help / available tasks
  build:qcow2:clean        Reset build state
  build:qcow2:image        Build QCOW2 (nix → VM configure → package)
  build:qcow2:container    Package QCOW2 as containerDisk
  build:qcow2:login        Authenticate to registry (Docker Hub / GHCR)
  build:qcow2:push         Push container to registry
  build:qcow2:start        Boot image for local development
  build:qcow2:ssh          SSH into VM
  build:qcow2:stop         Graceful shutdown
  build:qcow2:publish      Full automation: image → container → login → push

Pipeline Tasks (internal, run via --all):
  _build:qcow2:env             Export shared environment variables
  _build:qcow2:nix             Nix build QCOW2
  _build:qcow2:cloudinit       Generate cloud-init ISO
  _build:qcow2:img:reset       Reset image to pristine
  _build:qcow2:vm:boot         Boot VM with EFI
  _build:qcow2:vm:wait         Wait for SSH ready
  _build:qcow2:vm:sync         Rsync source to VM
  _build:qcow2:vm:gc           Garbage collect nix store
  _build:qcow2:vm:zero         Zero free space
  _build:qcow2:vm:halt         Shutdown VM
  _build:qcow2:img:clean       Clean credentials
  _build:qcow2:img:compress    ZSTD compress
  _build:qcow2:img:sparsify    Reclaim sparse space
  _build:qcow2:tmp:clean       Remove temp files
  _build:qcow2:verify          Verify output

Debug Tasks:
  _build:qcow2:debug:log       View boot log
  _build:qcow2:vm:kill         Force kill VM

Configuration: example.env (defaults) → .env (overrides)
SSH: ssh localhost (devshell configures port 2222)
Registry: docker.io/containercraft/konductor:latest-qcow2
```

---

## Pipeline Tasks

### _build:qcow2:env

Export shared environment variables. Runs first, persists to all subsequent tasks in session.

```sh {"name":"_build:qcow2:env"}
# Shared variables - exported once, inherited by all tasks in --all session
export QCOW2_OUTPUT="konductor-$(date +%Y%m%d).qcow2"
export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-docker.io}"
export CONTAINER_IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
export CONTAINER_TAG="${CONTAINER_TAG:-latest-qcow2}"
export FULL_IMAGE="${CONTAINER_REGISTRY}/${CONTAINER_IMAGE}:${CONTAINER_TAG}"

echo "=== Build Environment ==="
echo "QCOW2_OUTPUT: $QCOW2_OUTPUT"
echo "FULL_IMAGE: $FULL_IMAGE"
```

---

### _build:qcow2:nix

Nix builds the NixOS system closure → `result/nixos.qcow2`.

```sh {"name":"_build:qcow2:nix","tag":"requires:nix"}
set -e
nix build .#qcow2 --no-warn-dirty

# result/ is a symlink to read-only nix store
# Create CoW overlay (stores only changed blocks, not full copy)
BACKING_FILE="$(readlink -f result/nixos.qcow2)"
rm -rf result.writable 2>/dev/null || true
mkdir -p result.writable
qemu-img create -f qcow2 -b "$BACKING_FILE" -F qcow2 result.writable/nixos.qcow2

# Symlink result/ to overlay (tasks expect result/nixos.qcow2)
rm -f result 2>/dev/null || true
ln -sf result.writable result

# Set ownership for current user (QEMU write access)
chown -R "$(id -u):$(id -g)" result.writable/
chmod -R u+rwX result.writable/
```

---

### _build:qcow2:cloudinit

Generate ephemeral cloud-init ISO with SSH credentials.

```sh {"name":"_build:qcow2:cloudinit"}
set -e

# Requires: nix develop .#konductor
[ -n "$OVMF_CODE" ] || { echo "Error: OVMF_CODE not set. Run: nix develop .#konductor"; exit 1; }
[ -n "$OVMF_VARS" ] || { echo "Error: OVMF_VARS not set. Run: nix develop .#konductor"; exit 1; }
[ -f "$HOME/.ssh/id_ed25519.pub" ] || { echo "Error: ~/.ssh/id_ed25519.pub not found"; exit 1; }

mkdir -p /tmp/konductor-build-cloud-init
BUILD_SSH_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
BUILD_USER="$USER"
BUILD_UID="$(id -u)"

cp "$OVMF_VARS" /tmp/konductor-build-cloud-init/OVMF_VARS.fd
chmod 644 /tmp/konductor-build-cloud-init/OVMF_VARS.fd

cat > /tmp/konductor-build-cloud-init/meta-data << EOF
instance-id: konductor-$(date +%s)
local-hostname: konductor
EOF

cat > /tmp/konductor-build-cloud-init/user-data << EOF
#cloud-config
# All users in kc2 group (GID 1001) for shared directory access
users:
  - name: $BUILD_USER
    uid: $BUILD_UID
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $BUILD_SSH_KEY
  - name: kc2
    groups: docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
  - name: kc2admin
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $BUILD_SSH_KEY
runcmd:
  - mkdir -p /workspace
  - mount -t 9p -o trans=virtio host /workspace || true
EOF

genisoimage -output /tmp/konductor-build-cloud-init/seed.iso \
    -volid cidata -joliet -rock -input-charset utf-8 \
    /tmp/konductor-build-cloud-init/user-data /tmp/konductor-build-cloud-init/meta-data \
    || { echo "Error: Failed to create cloud-init ISO"; exit 1; }
```

---

### _build:qcow2:img:reset

Reset image to pristine state before first boot.

```sh {"name":"_build:qcow2:img:reset","tag":"requires:guestfs"}
set -e
export LIBGUESTFS_BACKEND=direct
GUESTMOUNT="$(which guestmount)"
GUESTUNMOUNT="$(which guestunmount)"
sudo mkdir -p /tmp/nixmount
sudo "$GUESTMOUNT" -a result/nixos.qcow2 -m /dev/sda2 /tmp/nixmount
trap 'sudo "$GUESTUNMOUNT" /tmp/nixmount 2>/dev/null || true' EXIT
sudo rm -f /tmp/nixmount/etc/ssh/ssh_host_* /tmp/nixmount/etc/machine-id
sudo rm -rf /tmp/nixmount/var/lib/cloud /tmp/nixmount/var/log/journal/*
sudo "$GUESTUNMOUNT" /tmp/nixmount
trap - EXIT
sync && sleep 1
```

---

### _build:qcow2:vm:boot

Boot VM with EFI firmware and 9p workspace mount.

```sh {"name":"_build:qcow2:vm:boot","tag":"requires:kvm"}
set -e
ss -tlnp 2>/dev/null | grep -q ':2222 ' && { echo "Error: Port 2222 in use"; exit 1; }
qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -m 8192 \
    -cpu host \
    -smp "$(nproc)" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file=/tmp/konductor-build-cloud-init/OVMF_VARS.fd \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2 \
    -drive file=/tmp/konductor-build-cloud-init/seed.iso,media=cdrom \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr \
    -daemonize \
    -pidfile /tmp/konductor-build-vm.pid \
    -serial file:/tmp/konductor-build-vm.log \
    -display none
sleep 1
[ -f /tmp/konductor-build-vm.pid ] && kill -0 "$(cat /tmp/konductor-build-vm.pid)" 2>/dev/null \
    || { echo "Error: QEMU failed to start. Check: tail /tmp/konductor-build-vm.log"; exit 1; }
```

---

### _build:qcow2:vm:wait

Wait for VM SSH to become available.

```sh {"name":"_build:qcow2:vm:wait","tag":"duration:slow"}
timeout 180 bash -c 'until ssh localhost true 2>/dev/null; do sleep 3; done' || { echo "Error: VM failed to boot within 3 minutes"; exit 1; }
```

---

### _build:qcow2:vm:sync

Rsync source to `/opt/konductor`.

```sh {"name":"_build:qcow2:vm:sync"}
set -e
ssh localhost 'sudo rm -rf /opt/konductor && sudo mkdir -p /opt/konductor'
ssh localhost 'sudo rsync -a \
    --exclude={result,result.writable,.direnv,.env,.env.local,node_modules,__pycache__,.pytest_cache,.mypy_cache,.coverage,.devcontainer,.claude,.mcp.json,.vscode,.idea,"*.tmp","*.pyc","*.bak","*.log",".DS_Store","*.qcow2","*.qcow2.tmp",".mise.toml.disabled"} \
    /workspace/ /opt/konductor/'
# Use kc2:kc2 (1001:1001) for consistent shared group ownership
ssh localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R kc2:kc2 /opt/konductor'
ssh localhost 'cd /opt/konductor && sudo git gc --aggressive --prune=now'
```

---

### _build:qcow2:vm:gc

Garbage collect nix store and clear caches.

```sh {"name":"_build:qcow2:vm:gc"}
set -e
ssh localhost 'sudo nix-collect-garbage -d'
ssh localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
ssh localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

---

### _build:qcow2:vm:zero

Zero free space for optimal compression.

```sh {"name":"_build:qcow2:vm:zero","tag":"duration:slow"}
set -e
ssh localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

---

### _build:qcow2:vm:halt

Graceful VM shutdown.

```sh {"name":"_build:qcow2:vm:halt"}
if [ -f /tmp/konductor-build-vm.pid ]; then
    PID=$(cat /tmp/konductor-build-vm.pid)
    if kill -0 "$PID" 2>/dev/null; then
        ssh localhost 'sudo poweroff' 2>/dev/null || true
        sleep 5
        kill "$PID" 2>/dev/null || true
    fi
    rm -f /tmp/konductor-build-vm.pid
fi
```

---

### _build:qcow2:img:clean

Clean credentials and build artifacts from final image.

```sh {"name":"_build:qcow2:img:clean","tag":"requires:guestfs"}
set -e
export LIBGUESTFS_BACKEND=direct
GUESTMOUNT="$(which guestmount)"
GUESTUNMOUNT="$(which guestunmount)"
sudo mkdir -p /tmp/nixmount
sudo "$GUESTMOUNT" -a result/nixos.qcow2 -m /dev/sda2 /tmp/nixmount
trap 'sudo "$GUESTUNMOUNT" /tmp/nixmount 2>/dev/null || true; sudo rmdir /tmp/nixmount 2>/dev/null || true' EXIT
sudo rm -f /tmp/nixmount/etc/ssh/ssh_host_* /tmp/nixmount/etc/machine-id
sudo rm -rf /tmp/nixmount/var/lib/cloud /tmp/nixmount/var/log/journal/*
sudo rm -rf /tmp/nixmount/root/.ssh /tmp/nixmount/home/*/.ssh 2>/dev/null || true
sudo rm -f /tmp/nixmount/root/.gitconfig /tmp/nixmount/home/*/.gitconfig 2>/dev/null || true
sudo "$GUESTUNMOUNT" /tmp/nixmount
trap - EXIT
sync && sleep 1
sudo rmdir /tmp/nixmount 2>/dev/null || true
```

---

### _build:qcow2:img:compress

ZSTD compress QCOW2.

```sh {"name":"_build:qcow2:img:compress","tag":"duration:slow"}
set -e
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 "${QCOW2_OUTPUT}.tmp"
```

---

### _build:qcow2:img:sparsify

Sparsify to reclaim zero-filled space.

```sh {"name":"_build:qcow2:img:sparsify","tag":"duration:slow,requires:guestfs"}
set -e
export LIBGUESTFS_BACKEND=direct
VIRT_SPARSIFY="$(which virt-sparsify)"
sudo "$VIRT_SPARSIFY" --compress --convert qcow2 -o compression_type=zstd "${QCOW2_OUTPUT}.tmp" "$QCOW2_OUTPUT"
rm -f "${QCOW2_OUTPUT}.tmp"
```

---

### _build:qcow2:tmp:clean

Remove temporary build files.

```sh {"name":"_build:qcow2:tmp:clean"}
rm -rf /tmp/konductor-build-cloud-init /tmp/konductor-build-vm.log
```

---

### _build:qcow2:verify

Verify build output with SHA256 checksum.

```sh {"name":"_build:qcow2:verify","tag":"type:readonly","interactive":"false"}
set -e
[ -f "$QCOW2_OUTPUT" ] || { echo "Error: $QCOW2_OUTPUT not found"; exit 1; }
echo "=== QCOW2 Build Complete ==="
echo "FILE: $QCOW2_OUTPUT"
echo "SIZE: $(du -h "$QCOW2_OUTPUT" | cut -f1)"
echo "SHA256: $(sha256sum "$QCOW2_OUTPUT" | cut -d' ' -f1)"
qemu-img info "$QCOW2_OUTPUT" | grep -E '^(file format|virtual size|disk size|cluster_size)'
```

---

## Debug Tools

### _build:qcow2:debug:log

View VM boot log.

```sh {"name":"_build:qcow2:debug:log","excludeFromRunAll":"true","tag":"type:debug"}
tail -100 /tmp/konductor-build-vm.log
```

`runme run _build:qcow2:debug:log`

---

### _build:qcow2:vm:kill

Force kill stuck VM.

```sh {"name":"_build:qcow2:vm:kill","excludeFromRunAll":"true","tag":"type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f /tmp/konductor-build-vm.pid
```

`runme run _build:qcow2:vm:kill`
