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
- [Supply Chain Provenance](#supply-chain-provenance)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Pipeline Tasks](#pipeline-tasks)
- [Debug Tools](#debug-tools)

---

## Output

| Artifact | Description |
|----------|-------------|
| `konductor.qcow2` | ZSTD-compressed QCOW2 (~4GB) |
| `registry.docker.arpa/.../konductor:latest-qcow2` | KubeVirt containerDisk |
| `registry.docker.arpa/.../konductor:git-<commit>` | Git commit tag |
| `registry.docker.arpa/.../konductor:nix-<drv>` | Nix derivation tag |

The image includes:

- NixOS with cloud-init
- Full Konductor environment pre-installed (built natively via `nixos-rebuild switch`)
- Pre-cached devshells: `default`, `full`, `konductor` (airgap-ready)
- Languages: Python, Go, Node.js, Rust
- IDE: Neovim, tmux
- Self-hosting: Docker, QEMU, libvirt, Buildkit
- Users: `kc2`, `kc2admin`, `runner`
- Source: `/opt/konductor` (git history preserved for verification)

---

## Supply Chain Provenance

Single file `.konductor` accumulates through the supply chain:

```text
SOURCE ────► NIX ────► BUILD ────► SEAL ────► OCI ────► PUSH
   │          │          │           │          │         │
   ▼          ▼          ▼           ▼          ▼         ▼
┌────────────────────────────────────────────────────────────┐
│ .konductor                                                 │
├────────────────────────────────────────────────────────────┤
│ git_commit     ✓                                           │
│ git_dirty      ✓  (trust gate: 0 = reproducible)           │
│ nix_version         ✓                                      │
│ nix_hash            ✓                                      │
│ nix_drv             ✓  (reproducible build ID)             │
│ flake_lock_sha256   ✓                                      │
│ build_date               ✓                                 │
│ build_host               ✓                                 │
│ strict                   ✓  (KONDUCTOR_STRICT env)         │
│ image_sha256                  ✓                            │
│ image_size                    ✓                            │
│ oci_image                          ✓                       │
│ oci_tags                           ✓                       │
│ oci_digest                                   ✓             │
└────────────────────────────────────────────────────────────┘
```

### Deterministic Identifiers

| ID | Example | Reproducible | Use |
|----|---------|--------------|-----|
| `git-<7>` | `git-b7c2ab9` | Yes (if !dirty) | OCI tag, source trace |
| `nix-<12>` | `nix-ish8abfw47k7` | Yes | OCI tag, build ID |
| `sha-<12>` | `sha-def456abc123` | Yes | Content verification |

### Locations

| Location | Contents |
|----------|----------|
| `/.konductor` (inside VM) | git, nix, build, oci_image, oci_tags |
| `/disk/.konductor` (in OCI) | above + image_sha256, image_size, oci_digest |
| `/disk/build.log` (in OCI) | Serial console capture |

### Self-Pull from Running VM

```bash {"excludeFromRunAll":"true","name":"example:self-pull"}
# Parse provenance (run inside a Konductor VM)
oci_image=$(sed -n 's/^oci_image = "\(.*\)"$/\1/p' /.konductor)
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)

# Pull source container
docker pull "${oci_image}:git-${git_commit:0:7}"
```

### Example

```toml
[konductor]
git_commit = "b7c2ab9def456789..."
git_branch = "main"
git_remote = "https://github.com/containercraft/konductor.git"
git_dirty = 0
nix_version = "2.24.0"
nix_hash = "sha256-Syola5vIforGUKQxoj9Mp8pC42OMHLepe1O41/gI8ZQ="
nix_drv = "ish8abfw47k70cw4il324sr6fqz4wdvn"
flake_lock_sha256 = "abc123def456..."
build_date = "2025-01-22T10:30:00-08:00"
build_host = "konductor-builder"
build_user = "runner"
qemu = "8.2.0"
strict = false
oci_image = "registry.docker.arpa/containercraft/konductor"
oci_tags = ["latest-qcow2", "git-b7c2ab9", "nix-ish8abfw47k7"]
image_sha256 = "def456..."
image_size = "3.8G"
oci_digest = "sha256:abc123..."
```

---

## Prerequisites

All prerequisites are provided by `nix develop .#konductor` (devshell).

| Tool | Purpose |
|------|---------|
| `nix` | Build NixOS system closure |
| `qemu-system-x86_64` | Run build VM with KVM acceleration |
| `OVMF` | EFI firmware (`$OVMF_CODE`, `$OVMF_VARS`) |
| `guestfs-tools` | Mount and optimize QCOW2 images |
| `genisoimage` | Create cloud-init ISO |
| `docker` | Build containerDisk image |
| `skopeo` | Push to registry with multi-tag |
| SSH | `ssh localhost` → port 2222 |

---

## Quick Start

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  build:qcow2                    Show this help                              │
│    ├── :rebase                  Rebuild NixOS host from flake (dogfood)     │
│    ├── :clean                   Reset build state                           │
│    ├── :image                   Build QCOW2 (nix → VM configure → seal)     │
│    ├── :container               Package QCOW2 as containerDisk              │
│    ├── :login                   Authenticate to registry                    │
│    ├── :push                    Push with git/nix/latest tags               │
│    ├── :publish                 Full pipeline: image → container → push     │
│    ├── :promote                 Copy to public registry (docker.io)         │
│    ├── :start                   Boot image for local development            │
│    ├── :ssh                     SSH into running VM                         │
│    └── :stop                    Graceful VM shutdown                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### build:qcow2

```sh {"name":"build:qcow2","excludeFromRunAll":"true","tag":"type:entry"}
cat << 'EOF'
build:qcow2 - Konductor QCOW2 Build

Usage: runme run build:qcow2:<task>

Tasks:
  :rebase     Rebuild NixOS host from flake
  :clean      Reset build state
  :image      Build QCOW2
  :container  Package as containerDisk
  :login      Authenticate to registry
  :push       Push with multi-tag (git/nix/latest)
  :publish    Full pipeline
  :promote    Copy to public registry
  :start      Boot for development
  :ssh        SSH into VM
  :stop       Shutdown VM

Workflow:
  1. runme run build:qcow2:publish    # Build and push to local Zot
  2. kubectl apply -k deploy/kubevirt # Deploy to KubeVirt
  3. runme run build:qcow2:promote    # Promote to docker.io

Tags pushed:
  - latest-qcow2           (convenience)
  - git-<commit>           (source trace)
  - nix-<drv>              (reproducible build ID)

Skip Flags:
  SKIP_NIX_BUILD=true    Reuse existing result/
  SKIP_VM_PHASE=true     Reuse existing image
  SKIP_COMPRESS=true     Skip ZSTD compression
EOF
```

---

### build:qcow2:clean

```sh {"name":"build:qcow2:clean","excludeFromRunAll":"true","tag":"type:entry,type:destructive"}
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo umount -f "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
fusermount -uz "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
sudo rm -rf "${QCOW2_MOUNT:-/tmp/nixmount}" "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -rf result result.writable konductor.qcow2 konductor.qcow2.tmp .konductor .nix_drv
```

---

### build:qcow2:rebase

Rebuild NixOS host from flake.

```sh {"name":"build:qcow2:rebase","excludeFromRunAll":"true","tag":"type:entry,requires:nixos"}
set -e
sudo nixos-rebuild switch --flake .#konductor
echo "Run 'direnv reload' to pick up changes"
```

---

### build:qcow2:image

Build QCOW2: nix → VM configure → seal → verify.

```sh {"name":"build:qcow2:image","excludeFromRunAll":"true","tag":"type:entry"}
set -e
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:stop
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:clean
runme run --filename "$QCOW2_BUILD_FILE" --all
```

---

### build:qcow2:container

Package QCOW2 as containerDisk.

```sh {"name":"build:qcow2:container","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
FULL_IMAGE="${CONTAINER_REGISTRY:-registry.docker.arpa}/${CONTAINER_IMAGE:-containercraft/konductor}:${CONTAINER_TAG:-latest-qcow2}"

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
```

---

### build:qcow2:login

Authenticate to container registry.

```sh {"name":"build:qcow2:login","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"

if [[ "$REGISTRY" == "registry.docker.arpa" ]] || [[ "$REGISTRY" =~ ^registry\..+\.sslip\.io$ ]]; then
    if jq -e ".auths[\"$REGISTRY\"]" ~/.docker/config.json &>/dev/null 2>&1; then
        exit 0
    fi
    CERT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/certs.d/$REGISTRY"
    mkdir -p "$CERT_DIR"
    kubectl --context "${REGISTRY_K8S_CONTEXT:-admin@docker-dev}" \
        get secret gateway-tls-https -n envoy-gateway-system \
        -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CERT_DIR/ca.crt"
    echo "$REGISTRY_PASSWORD" | skopeo login "$REGISTRY" \
        --username "${REGISTRY_USERNAME:-admin}" --password-stdin \
        --cert-dir "$CERT_DIR" --compat-auth-file ~/.docker/config.json
elif [[ "$REGISTRY" == "docker.io" ]]; then
    if jq -e '.auths["https://index.docker.io/v1/"]' ~/.docker/config.json &>/dev/null 2>&1; then
        exit 0
    fi
    [ -n "$DOCKER_TOKEN" ] || { echo "Error: DOCKER_TOKEN not set"; exit 1; }
    echo "$DOCKER_TOKEN" | docker login docker.io -u "${DOCKER_USERNAME:-containercraft}" --password-stdin
elif [[ "$REGISTRY" == "ghcr.io" ]]; then
    if jq -e '.auths["ghcr.io"]' ~/.docker/config.json &>/dev/null 2>&1; then
        exit 0
    fi
    [ -n "$GITHUB_TOKEN" ] || { echo "Error: GITHUB_TOKEN not set"; exit 1; }
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-github}" --password-stdin
else
    echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "${REGISTRY_USERNAME:-admin}" --password-stdin
fi
```

---

### build:qcow2:push

Push container with multi-tag (git/nix/latest).

```sh {"name":"build:qcow2:push","excludeFromRunAll":"true","tag":"requires:docker"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
BASE_TAG="${CONTAINER_TAG:-latest-qcow2}"
CERT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/certs.d/$REGISTRY"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

# Build tag list
TAGS=("$BASE_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("git-${git_commit:0:7}")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("nix-${nix_drv:0:12}")
fi

# Push with all tags
FULL_IMAGE="$REGISTRY/$IMAGE:$BASE_TAG"
docker image inspect "$FULL_IMAGE" &>/dev/null || { echo "Error: $FULL_IMAGE not found"; exit 1; }

for tag in "${TAGS[@]}"; do
    docker tag "$FULL_IMAGE" "$REGISTRY/$IMAGE:$tag"
    skopeo copy --dest-cert-dir "$CERT_DIR" \
        docker-daemon:"$REGISTRY/$IMAGE:$tag" \
        docker://"$REGISTRY/$IMAGE:$tag"
done

# Get digest and update .konductor
OCI_DIGEST=$(skopeo inspect --cert-dir "$CERT_DIR" docker://"$FULL_IMAGE" | jq -r '.Digest')
cat >> .konductor << EOF
oci_digest = "$OCI_DIGEST"
EOF

# Display
echo "Pushed: $REGISTRY/$IMAGE"
printf "  %s\n" "${TAGS[@]}"
echo "Digest: $OCI_DIGEST"
```

---

### build:qcow2:start

Boot image for local development.

```sh {"name":"build:qcow2:start","excludeFromRunAll":"true","tag":"type:entry"}
set -e
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. Use: ssh localhost"
    exit 0
fi
[ -f result/nixos.qcow2 ] || { echo "No image. Run build:qcow2:image first."; exit 1; }

runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:clean
runme run --filename "$QCOW2_BUILD_FILE" _build:qcow2:cloudinit
runme run --filename "$QCOW2_BUILD_FILE" _build:qcow2:vm:boot
runme run --filename "$QCOW2_BUILD_FILE" _build:qcow2:vm:wait
echo "VM ready: ssh localhost"
```

---

### build:qcow2:ssh

```sh {"name":"build:qcow2:ssh","excludeFromRunAll":"true","tag":"type:entry"}
ssh localhost
```

---

### build:qcow2:stop

```sh {"name":"build:qcow2:stop","excludeFromRunAll":"true","tag":"type:entry"}
runme run --filename "$QCOW2_BUILD_FILE" _build:qcow2:vm:halt
```

---

### build:qcow2:publish

Full pipeline: clean → image → container → login → push.

```sh {"name":"build:qcow2:publish","excludeFromRunAll":"true","tag":"type:entry"}
set -e
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:clean
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:image
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:container
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:login
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:push
cat .konductor
```

---

### build:qcow2:promote

Copy to public registry.

```sh {"name":"build:qcow2:promote","excludeFromRunAll":"true","tag":"type:entry"}
set -e
SRC_REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
SRC_IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
SRC_TAG="${CONTAINER_TAG:-latest-qcow2}"
SRC_CERT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/certs.d/$SRC_REGISTRY"

DST_REGISTRY="${PROMOTE_REGISTRY:-docker.io}"
DST_IMAGE="${PROMOTE_IMAGE:-containercraft/konductor}"
DST_TAG="${PROMOTE_TAG:-latest-qcow2}"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance for additional tags
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

# Verify source exists
skopeo inspect --cert-dir "$SRC_CERT_DIR" docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" &>/dev/null \
    || { echo "Error: Source not found. Run build:qcow2:publish first."; exit 1; }

# Authenticate to destination
if [[ "$DST_REGISTRY" == "docker.io" ]]; then
    [ -n "$DOCKER_TOKEN" ] || { echo "Error: DOCKER_TOKEN not set"; exit 1; }
    echo "$DOCKER_TOKEN" | skopeo login docker.io -u "${DOCKER_USERNAME:-containercraft}" --password-stdin
elif [[ "$DST_REGISTRY" == "ghcr.io" ]]; then
    [ -n "$GITHUB_TOKEN" ] || { echo "Error: GITHUB_TOKEN not set"; exit 1; }
    echo "$GITHUB_TOKEN" | skopeo login ghcr.io -u "${GITHUB_ACTOR:-github}" --password-stdin
fi

# Build tag list
TAGS=("$DST_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("git-${git_commit:0:7}")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("nix-${nix_drv:0:12}")
fi

# Copy with all tags
for tag in "${TAGS[@]}"; do
    skopeo copy --src-cert-dir "$SRC_CERT_DIR" \
        docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" \
        docker://"$DST_REGISTRY/$DST_IMAGE:$tag"
done

echo "Promoted: $DST_REGISTRY/$DST_IMAGE"
printf "  %s\n" "${TAGS[@]}"
skopeo inspect docker://"$DST_REGISTRY/$DST_IMAGE:$DST_TAG" | jq '{Digest, Created}'
```

---

## Task Reference

```text
Entry Points:
  build:qcow2              Show help
  build:qcow2:rebase       Rebuild NixOS host from flake
  build:qcow2:clean        Reset build state
  build:qcow2:image        Build QCOW2
  build:qcow2:container    Package as containerDisk
  build:qcow2:login        Authenticate to registry
  build:qcow2:push         Push with multi-tag
  build:qcow2:publish      Full pipeline
  build:qcow2:promote      Copy to public registry
  build:qcow2:start        Boot for development
  build:qcow2:ssh          SSH into VM
  build:qcow2:stop         Shutdown VM

Pipeline Tasks (run via --all):
  _build:qcow2:preflight       Validate environment
  _build:qcow2:nix             Build NixOS closure + capture nix_drv
  _build:qcow2:cloudinit       Generate cloud-init ISO
  _build:qcow2:img:reset       Reset image to pristine
  _build:qcow2:vm:boot         Boot VM
  _build:qcow2:vm:wait         Wait for SSH
  _build:qcow2:vm:sync         Rsync source to VM
  _build:qcow2:vm:rebuild      nixos-rebuild switch from flake (native build)
  _build:qcow2:vm:provenance   Write /.konductor
  _build:qcow2:vm:gc           Garbage collect
  _build:qcow2:vm:zero         Zero free space
  _build:qcow2:vm:halt         Shutdown VM
  _build:qcow2:img:clean       Clean credentials
  _build:qcow2:img:compress    ZSTD compress
  _build:qcow2:img:sparsify    Reclaim sparse space
  _build:qcow2:tmp:clean       Remove temp files
  _build:qcow2:verify          Append post-seal fields

Debug:
  _build:qcow2:debug:log     View boot log
  _build:qcow2:vm:kill       Force kill VM
```

---

## Pipeline Tasks

### _build:qcow2:preflight

Validate environment.

```sh {"name":"_build:qcow2:preflight"}
set -e
ERRORS=0

runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:clean

for cmd in $QCOW2_REQUIRED_BINS; do
    command -v "$cmd" &>/dev/null && printf "✓ %s\n" "$cmd" || { printf "✗ %s\n" "$cmd"; ((ERRORS++)); }
done

for var in $QCOW2_REQUIRED_FILE_VARS; do
    val="${!var}"; [ -n "$val" ] && [ -f "$val" ] && printf "✓ %s\n" "$var" || { printf "✗ %s\n" "$var"; ((ERRORS++)); }
done

for var in $QCOW2_REQUIRED_VARS; do
    [ -n "${!var}" ] && printf "✓ %s\n" "$var" || { printf "✗ %s\n" "$var"; ((ERRORS++)); }
done

SSH_PUBKEY="${QCOW2_SSH_KEY_DIR:-$HOME/.ssh}/id_ed25519.pub"
ssh-keygen -l -f "$SSH_PUBKEY" &>/dev/null && printf "✓ %s\n" "$SSH_PUBKEY" || { printf "✗ %s\n" "$SSH_PUBKEY"; ((ERRORS++)); }

[ -r /dev/kvm ] && [ -w /dev/kvm ] && printf "✓ /dev/kvm\n" || { printf "✗ /dev/kvm\n"; ((ERRORS++)); }

DISK_AVAIL_GB=$(df -BG --output=avail . | tail -1 | tr -d ' G')
[ "$DISK_AVAIL_GB" -ge "${QCOW2_MIN_DISK_GB:-100}" ] && printf "✓ disk %sGB\n" "$DISK_AVAIL_GB" || { printf "✗ disk %sGB\n" "$DISK_AVAIL_GB"; ((ERRORS++)); }

MEM_AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
[ "$MEM_AVAIL_MB" -ge "${QCOW2_MIN_MEM_MB:-8192}" ] && printf "✓ memory %sMB\n" "$MEM_AVAIL_MB" || { printf "✗ memory %sMB\n" "$MEM_AVAIL_MB"; ((ERRORS++)); }

[ "$ERRORS" -eq 0 ] || { echo "$ERRORS error(s)"; exit 1; }
```

---

### _build:qcow2:nix

Build NixOS closure and capture nix_drv.

```sh {"name":"_build:qcow2:nix","tag":"requires:nix"}
set -e
if [ "${SKIP_NIX_BUILD:-false}" = "true" ] && [ -d result.writable ]; then
    echo "SKIP_NIX_BUILD: reusing existing"
    exit 0
fi

# Capture nix_drv before build (derivation hash is known from eval)
NIX_DRV=$(nix path-info --derivation .#qcow2 2>/dev/null | head -1 | xargs basename | cut -d- -f1)
echo "$NIX_DRV" > .nix_drv

nix build .#qcow2 --no-warn-dirty

BACKING_FILE="$(readlink -f result/nixos.qcow2)"
rm -rf result.writable && mkdir -p result.writable
qemu-img create -f qcow2 -b "$BACKING_FILE" -F qcow2 result.writable/nixos.qcow2
rm -f result && ln -sf result.writable result
chown -R "$(id -u):$(id -g)" result.writable/
```

---

### _build:qcow2:cloudinit

Generate cloud-init ISO.

```sh {"name":"_build:qcow2:cloudinit"}
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
  - name: $USER
    uid: $(id -u)
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
  - name: kc2admin
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
runcmd:
  - mkdir -p /workspace
  - mount -t 9p -o trans=virtio host /workspace || true
EOF

genisoimage -output "$CLOUD_INIT_DIR/seed.iso" \
    -volid cidata -joliet -rock -input-charset utf-8 \
    "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
```

---

### _build:qcow2:img:reset

Reset image to pristine state.

```sh {"name":"_build:qcow2:img:reset","tag":"requires:guestfs"}
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

### _build:qcow2:vm:boot

Boot VM.

```sh {"name":"_build:qcow2:vm:boot","tag":"requires:kvm"}
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
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$CLOUD_INIT_DIR/OVMF_VARS.fd" \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2,cache=writeback,aio=io_uring,discard=unmap,detect-zeroes=unmap \
    -drive file="$CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,hostfwd=tcp::${QCOW2_SSH_PORT:-2222}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr,multidevs=remap \
    -daemonize \
    -pidfile "$PIDFILE" \
    -serial file:"${QCOW2_LOGFILE:-build-vm.log}" \
    -display none

sleep 1
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
    || { echo "QEMU failed"; exit 1; }
```

---

### _build:qcow2:vm:wait

Wait for SSH.

```sh {"name":"_build:qcow2:vm:wait","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
timeout "${QCOW2_SSH_TIMEOUT:-300}" bash -c 'until ssh localhost true 2>/dev/null; do sleep 3; done' \
    || { echo "SSH timeout"; exit 1; }
```

---

### _build:qcow2:vm:sync

Sync source to VM. Tries git clone first (preserves history), falls back to rsync.

<!-- TODO: SSH key injection for private repository access
  - Pass SSH private key via cloud-init user-data (from CI runner secrets)
  - Write to /root/.ssh/id_ed25519 with proper permissions
  - Add git host to known_hosts
  - Enables authenticated git clone for private repos (git.braincraft.io)
  - Key should be ephemeral (cleaned in img:clean phase)
-->

```sh {"name":"_build:qcow2:vm:sync"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

ssh localhost 'sudo rm -rf /opt/konductor'

CLONE_OK=false
if [ -n "$GIT_REMOTE" ] && [ -n "$GIT_COMMIT" ]; then
    # Try git clone (preserves history for verify:konductor tasks)
    if ssh localhost "sudo git clone --no-checkout '$GIT_REMOTE' /opt/konductor 2>/dev/null" && \
       ssh localhost "cd /opt/konductor && sudo git checkout '$GIT_COMMIT' 2>/dev/null"; then
        CLONE_OK=true
    else
        ssh localhost 'sudo rm -rf /opt/konductor' 2>/dev/null || true
    fi
fi

if [ "$CLONE_OK" = "false" ]; then
    # Fallback: rsync with .git (if accessible locally)
    ssh localhost 'sudo mkdir -p /opt/konductor'
    ssh localhost 'sudo rsync -a \
        --exclude={result,result.writable,.direnv,.env,.env.local,node_modules,__pycache__,.pytest_cache,.mypy_cache,.coverage,.devcontainer,.claude,.mcp.json,.vscode,.idea,"*.tmp","*.pyc","*.bak","*.log",".DS_Store","*.qcow2","*.qcow2.tmp",www,.venv} \
        /workspace/ /opt/konductor/'
fi

ssh localhost 'sudo chmod -R a+rX /opt/konductor && sudo chown -R kc2:kc2 /opt/konductor'
```

---

### _build:qcow2:vm:rebuild

Run `nixos-rebuild switch` inside VM to build the devshell natively.

This ensures:
- Full Konductor environment is built natively inside the VM
- All nix store paths are pre-cached for airgap use
- The VM can reproduce itself from /opt/konductor

```sh {"name":"_build:qcow2:vm:rebuild","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

# Rebuild NixOS from the synced flake
ssh localhost 'cd /opt/konductor && sudo nixos-rebuild switch --flake .#konductor 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Pre-build devshells to cache their closures
# This ensures `nix develop` works offline
ssh localhost 'cd /opt/konductor && nix build --no-link .#devShells.x86_64-linux.default 2>&1 || true'
ssh localhost 'cd /opt/konductor && nix build --no-link .#devShells.x86_64-linux.full 2>&1 || true'
ssh localhost 'cd /opt/konductor && nix build --no-link .#devShells.x86_64-linux.konductor 2>&1 || true'

echo "VM rebuilt from /opt/konductor flake"
```

---

### _build:qcow2:vm:provenance

Write `/.konductor` inside VM.

```sh {"name":"_build:qcow2:vm:provenance"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

# Gather provenance
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
NIX_VERSION=$(nix --version 2>/dev/null | sed 's/nix (Nix) //' || echo "unknown")
NIX_HASH=$(nix flake metadata --json 2>/dev/null | jq -r '.locked.narHash // "unknown"')
NIX_DRV=$(cat .nix_drv 2>/dev/null || echo "unknown")
FLAKE_LOCK_SHA=$(sha256sum flake.lock 2>/dev/null | cut -d' ' -f1 || echo "unknown")
BUILD_DATE=$(date -Iseconds)
BUILD_HOST=$(hostname)
BUILD_USER="$USER"
QEMU_VER=$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //')
OCI_IMAGE="${CONTAINER_REGISTRY:-registry.docker.arpa}/${CONTAINER_IMAGE:-containercraft/konductor}"

# Build tag list for provenance
OCI_TAGS="[\"${CONTAINER_TAG:-latest-qcow2}\""
[ "$GIT_DIRTY" = "0" ] && [ "$GIT_COMMIT" != "unknown" ] && OCI_TAGS+=", \"git-${GIT_COMMIT:0:7}\""
[ "$NIX_DRV" != "unknown" ] && OCI_TAGS+=", \"nix-${NIX_DRV:0:12}\""
OCI_TAGS+="]"

# Write /.konductor inside VM
ssh localhost "sudo tee /.konductor > /dev/null" << EOF
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
strict = ${KONDUCTOR_STRICT:-false}
oci_image = "$OCI_IMAGE"
oci_tags = $OCI_TAGS
EOF
ssh localhost 'sudo chmod 644 /.konductor'

# Copy to host
ssh localhost 'cat /.konductor' > .konductor

# Serial output handled by konductor-provenance.service (systemd)
```

---

### _build:qcow2:vm:gc

Garbage collect.

```sh {"name":"_build:qcow2:vm:gc"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e
ssh localhost 'sudo nix-collect-garbage -d'
ssh localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
ssh localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

---

### _build:qcow2:vm:zero

Zero free space.

```sh {"name":"_build:qcow2:vm:zero","tag":"duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
ssh localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

---

### _build:qcow2:vm:halt

Shutdown VM.

```sh {"name":"_build:qcow2:vm:halt"}
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
[ -f "$PIDFILE" ] || exit 0

PID=$(cat "$PIDFILE")
if kill -0 "$PID" 2>/dev/null; then
    ssh localhost 'sudo poweroff' 2>/dev/null || true
    sleep 5
    kill "$PID" 2>/dev/null || true
fi
rm -f "$PIDFILE"
```

---

### _build:qcow2:img:clean

Clean credentials from image.

```sh {"name":"_build:qcow2:img:clean","tag":"requires:guestfs"}
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

### _build:qcow2:img:compress

ZSTD compress.

```sh {"name":"_build:qcow2:img:compress","tag":"duration:slow"}
set -e
if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    cp result/nixos.qcow2 konductor.qcow2
    exit 0
fi
qemu-img convert -c -p -m "$(nproc)" -O qcow2 -o compression_type=zstd result/nixos.qcow2 konductor.qcow2.tmp
```

---

### _build:qcow2:img:sparsify

Sparsify image.

```sh {"name":"_build:qcow2:img:sparsify","tag":"duration:slow,requires:guestfs"}
set -e
if [ "${SKIP_COMPRESS:-false}" = "true" ]; then
    exit 0
fi
export LIBGUESTFS_BACKEND=direct
sudo -E virt-sparsify --compress --convert qcow2 -o compression_type=zstd konductor.qcow2.tmp konductor.qcow2
rm -f konductor.qcow2.tmp
```

---

### _build:qcow2:tmp:clean

Remove temporary files.

```sh {"name":"_build:qcow2:tmp:clean"}
rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
rm -f .nix_drv
```

---

### _build:qcow2:verify

Append post-seal fields to .konductor.

```sh {"name":"_build:qcow2:verify","tag":"type:readonly"}
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

### _build:qcow2:debug:log

View boot log.

```sh {"name":"_build:qcow2:debug:log","excludeFromRunAll":"true","tag":"type:debug"}
tail -100 "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### _build:qcow2:vm:kill

Force kill VM.

```sh {"name":"_build:qcow2:vm:kill","excludeFromRunAll":"true","tag":"type:destructive"}
pkill -f "qemu-system.*nixos.qcow2" 2>/dev/null || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"
```
