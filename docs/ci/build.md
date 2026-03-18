---
cwd: ../..
shell: bash
skipPrompts: true
tag: k9:ci:qcow2:build,k9:ci:qcow2:build:qcow2
runme:
  version: v3
  debug: true
---

# Konductor QCOW2 Build Pipeline

Complete build pipeline: source → nix → VM configure → seal → compress → OCI containerDisk.

Phases run sequentially in document order via `runme run --all --tag=k9:ci:pipeline:all`.
Each phase is a named code block tagged for pipeline membership. Background daemons
use `background:true` for proper process lifecycle in runme's single-session mode.

## Contents

- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [Task Reference](#task-reference)
- [Build Phases](#build-phases)

---

## Quick Start

```bash
# Full build pipeline (clean → nix → VM → seal → container)
runme run --all --tag=k9:ci:pipeline:all --filename docs/ci/build.md

# Build QCOW2 only (no container packaging)
runme run --all --tag=k9:ci:pipeline:image --filename docs/ci/build.md

# Standalone preflight check
runme run --filename docs/ci/build.md k9:ci:qcow2:build:preflight
```

---

## Environment Variables

Set these in `.env` or export before running:

```bash
# Registry configuration
export CONTAINER_REGISTRY="registry.docker.arpa"
export CONTAINER_IMAGE="containercraft/konductor"
export CONTAINER_TAG="latest-qcow2"

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
Invocation:
  runme run --all --tag=pipeline:all --filename docs/ci/build.md    # Full pipeline
  runme run --all --tag=pipeline:image --filename docs/ci/build.md  # Image only (no container)
  runme run --filename docs/ci/build.md build:preflight             # Standalone preflight

Pipeline phases (document order, tag-selected):
  Tag: pipeline:all,pipeline:image
    _build:clean              Reset build state
    build:preflight           Validate environment
    _build:nix                Nix build + writable overlay
    _build:cloudinit          Generate cloud-init ISO
    _build:img:reset          Reset image to pristine state
    _build:vm:boot            Boot VM (virtiofsd + QEMU)
    _build:vm:wait            Wait for SSH
    _build:vm:sync            Sync source to VM
    _build:vm:rebuild         nixos-rebuild inside VM
    _build:vm:pki:test        PKI tests
    _build:vm:pki:status      PKI certificate status
    _build:vm:provenance      Write /.konductor provenance
    _build:vm:gc              Garbage collect
    _build:vm:zero            Zero free space
    _build:vm:halt            Shutdown VM
    _build:img:clean          Clean credentials from image
    _build:img:compress       ZSTD compress
    _build:img:sparsify       Sparsify image
    _build:tmp:clean          Remove temp files
    _build:verify             Append post-seal fields

  Tag: pipeline:all only
    _build:container          Package as OCI containerDisk
```

---

## Build Phases

### \_build:clean

Reset build state.

```bash {"name":"k9:ci:qcow2:build:_clean","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,type:destructive"}
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
# Stop virtiofsd daemon (system-scope transient unit, works headless in CI)
sudo systemctl stop virtiofsd-nixstore 2>/dev/null || true
sudo systemctl reset-failed virtiofsd-nixstore 2>/dev/null || true
sudo rm -f "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}" "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}.pid"
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo umount -f "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
fusermount -uz "${QCOW2_MOUNT:-/tmp/nixmount}" 2>/dev/null || true
sudo rm -rf "${QCOW2_MOUNT:-/tmp/nixmount}" "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
sudo rm -rf result result.writable konductor.qcow2 konductor.qcow2.tmp .konductor .nix_drv .system-toplevel
echo "✓ Clean"
```

---

### \_build:preflight

Validate environment (standalone — no cluster required).

```bash {"name":"k9:ci:qcow2:build:preflight","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
set -ex

echo "bash: $(which bash) (${BASH_VERSION})"

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

[ ! -e result ] && printf "✓ no result/\n" || { printf "✗ stale result/ exists (run _build:clean)\n"; ((ERRORS++)); }
[ ! -e result.writable ] && printf "✓ no result.writable/\n" || { printf "✗ stale result.writable/ exists\n"; ((ERRORS++)); }
[ ! -e konductor.qcow2 ] && printf "✓ no konductor.qcow2\n" || { printf "✗ stale konductor.qcow2 exists\n"; ((ERRORS++)); }
[ ! -e .konductor ] && printf "✓ no .konductor\n" || { printf "✗ stale .konductor exists\n"; ((ERRORS++)); }

# Working directory must be writable (nix build creates result symlink here)
if touch .write-test 2>/dev/null; then
    rm -f .write-test
    printf "✓ Working directory writable by $(whoami)\n"
else
    printf "✗ Working directory not writable by $(whoami) (owner: $(stat -c '%U:%G %a' .))\n"
    ((ERRORS++))
fi

# ─────────────────────────────────────────────────────────────────────
# REQUIRED BINARIES
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Environment validation:"

REQUIRED_BINS="${QCOW2_REQUIRED_BINS:-nix qemu-img qemu-system-x86_64 virtiofsd passt genisoimage guestmount guestunmount virt-sparsify ssh rsync timeout ss du sha256sum jq docker}"

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
      narHash: (.locked.narHash // "unlocked"),
      inputs: ([.locks.nodes | to_entries[] | select(.key | test("^root$") | not) | {
        (.key): {
          type: .value.locked.type,
          rev: (.value.locked.rev // "n/a"),
          narHash: (.value.locked.narHash // "n/a")
        }
      }] | add // {})
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
# RUNTIME ENVIRONMENT (fail-fast for late-stage failures)
# ─────────────────────────────────────────────────────────────────────
# These checks catch environment gaps that previously caused 160+ minute
# build cycles to fail at post-build phases (cluster:up, push, etc.)
echo ""
echo "Runtime environment:"

# OVMF firmware (required for QEMU VM boot)
[ -n "$OVMF_CODE" ] && [ -f "$OVMF_CODE" ] && printf "✓ OVMF_CODE=%s\n" "$OVMF_CODE" || { printf "✗ OVMF_CODE not set or missing\n"; ((ERRORS++)); }
[ -n "$OVMF_VARS" ] && [ -f "$OVMF_VARS" ] && printf "✓ OVMF_VARS=%s\n" "$OVMF_VARS" || { printf "✗ OVMF_VARS not set or missing\n"; ((ERRORS++)); }

# LD_LIBRARY_PATH — grpcio/pulumi need libstdc++.so.6 (cluster:up fails without it)
if [ -n "$LD_LIBRARY_PATH" ]; then
    _found_libstdcpp=false
    IFS=: read -ra _ldpaths <<< "$LD_LIBRARY_PATH"
    for _p in "${_ldpaths[@]}"; do
        [ -d "$_p" ] && ls "$_p"/libstdc++.so* >/dev/null 2>&1 && _found_libstdcpp=true && break
    done
    if [ "$_found_libstdcpp" = true ] || /usr/sbin/ldconfig -p 2>/dev/null | grep -q libstdc++; then
        printf "✓ LD_LIBRARY_PATH set, libstdc++.so found\n"
    else
        printf "✗ LD_LIBRARY_PATH set but libstdc++.so not found in paths\n"
        ((ERRORS++))
    fi
else
    printf "✗ LD_LIBRARY_PATH not set (pulumi/grpcio will fail at cluster:up)\n"
    ((ERRORS++))
fi

# DOCKER_HOST — docker commands fail without explicit host
if [ -n "$DOCKER_HOST" ]; then
    printf "✓ DOCKER_HOST=%s\n" "$DOCKER_HOST"
else
    printf "⚠ DOCKER_HOST not set (defaulting to unix:///var/run/docker.sock)\n"
fi

# Docker daemon reachable
if docker info &>/dev/null; then
    printf "✓ Docker daemon reachable\n"
else
    printf "✗ Docker daemon not reachable\n"
    ((ERRORS++))
fi

# DOCKER_BUILDKIT — required for multi-stage builds
[ "${DOCKER_BUILDKIT:-0}" = "1" ] && printf "✓ DOCKER_BUILDKIT=1\n" || printf "⚠ DOCKER_BUILDKIT not set (may affect build performance)\n"


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

### \_build:nix

Build NixOS closure and capture nix_drv.

```bash {"name":"k9:ci:qcow2:build:_nix","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,requires:nix"}
set -ex
if [ "${SKIP_NIX_BUILD:-false}" = "true" ] && [ -d result.writable ]; then
    echo "SKIP_NIX_BUILD: reusing existing"
    exit 0
fi

# Vendored inputs are required for offline builds.
if [ ! -f "_sources/catppuccin/flake.nix" ]; then
    echo "Error: vendored inputs missing. Run: runme run k9:ci:dev:vendor"
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

# Pre-build system toplevel so its closure is in the host nix store.
# When dev:vendor has been run, manifest.txt maps input names to nix store paths.
# The VM's --override-input uses those same store paths (via virtiofs overlay),
# so derivation hashes match and the VM gets full cache hits.
echo "Pre-building system toplevel for VM cache..."
OVERRIDE_INPUTS=""
if [ -f "_sources/manifest.txt" ]; then
    echo "Using vendored store paths from manifest.txt..."
    while read -r name spath; do
        OVERRIDE_INPUTS+=" --override-input $name path:$spath"
    done < _sources/manifest.txt
fi
nix build '.#nixosConfigurations.konductor.config.system.build.toplevel' --no-warn-dirty --no-link $OVERRIDE_INPUTS
nix build --no-link '.#devShells.x86_64-linux.default' --no-warn-dirty $OVERRIDE_INPUTS
nix build --no-link '.#devShells.x86_64-linux.full' --no-warn-dirty $OVERRIDE_INPUTS
nix build --no-link '.#devShells.x86_64-linux.konductor' --no-warn-dirty $OVERRIDE_INPUTS

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

### \_build:cloudinit

Generate cloud-init ISO.

```bash {"name":"k9:ci:qcow2:build:_cloudinit","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
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

### \_build:img:reset

Reset image to pristine state.

```bash {"name":"k9:ci:qcow2:build:_img-reset","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,requires:guestfs"}
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

### \_build:vm:boot

Boot VM with virtiofsd + QEMU.

```bash {"name":"k9:ci:qcow2:build:_vm-boot","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,requires:kvm"}
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

# ─────────────────────────────────────────────────────────────────────
# Start virtiofsd as a system-scope transient systemd unit (fully
# outside runme's process tree). System scope works headless in CI
# (no D-Bus user session required) and provides cgroup isolation,
# journald logging, and proper resource accounting.
# ─────────────────────────────────────────────────────────────────────
VIRTIOFS_SOCK="${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}"

# Clean stale socket and pid files (previous runs may leave these behind;
# virtiofsd refuses to overwrite a pid file it doesn't own)
sudo rm -f "$VIRTIOFS_SOCK" "${VIRTIOFS_SOCK}.pid"

# Resolve virtiofsd absolute path for sudo (root's PATH lacks user nix profiles)
VIRTIOFSD_BIN="$(command -v virtiofsd 2>/dev/null)" \
    || VIRTIOFSD_BIN="/run/current-system/sw/bin/virtiofsd" \
    && [ -x "$VIRTIOFSD_BIN" ] \
    || VIRTIOFSD_BIN="/etc/profiles/per-user/${USER}/bin/virtiofsd" \
    && [ -x "$VIRTIOFSD_BIN" ] \
    || { echo "✗ virtiofsd not found in PATH, /run/current-system/sw/bin, or user profile"; exit 1; }
echo "Using virtiofsd: $VIRTIOFSD_BIN"

sudo systemd-run --unit=virtiofsd-nixstore \
    --description="virtiofsd for konductor build" \
    --property=LimitNOFILE=1048576 \
    -- "$VIRTIOFSD_BIN" \
    --socket-path="$VIRTIOFS_SOCK" \
    --shared-dir=/nix \
    --sandbox=none \
    --seccomp=none \
    --readonly \
    --cache=always \
    --thread-pool-size=4 \
    --inode-file-handles=prefer \
    --announce-submounts

# Wait for socket (systemd-run returns before exec, socket appears async)
for i in $(seq 1 20); do
    [ -S "$VIRTIOFS_SOCK" ] && break
    sleep 0.5
done
[ -S "$VIRTIOFS_SOCK" ] || { echo "✗ virtiofsd socket not found at $VIRTIOFS_SOCK"; sudo systemctl status virtiofsd-nixstore --no-pager; sudo journalctl -u virtiofsd-nixstore --no-pager -n 10; exit 1; }
# Socket is root-owned (system-scope unit); make it accessible for QEMU (runs as user)
sudo chmod 0666 "$VIRTIOFS_SOCK"
echo "virtiofsd ready: $(sudo systemctl show virtiofsd-nixstore --property=MainPID --value)"

# ─────────────────────────────────────────────────────────────────────
# Launch QEMU with:
#   - iothread for virtio-blk (moves disk I/O off vCPU thread)
#   - multi-queue virtio-blk (parallel I/O across vCPUs)
#   - virtiofs for host nix store (replaces 9p, 3-5x faster)
#   - 9p for workspace (low throughput, acceptable for source sync)
# ─────────────────────────────────────────────────────────────────────
# TODO: Switch to passt networking once the image includes it (konductor.nix has passt added)
VM_MEMORY="${QCOW2_VM_MEMORY:-16384}"
qemu-system-x86_64 \
    -machine q35,accel=kvm,mem-merge=on \
    -m "$VM_MEMORY" \
    -cpu host \
    -smp "${QCOW2_VM_CPUS:-$VM_CPUS}" \
    -rtc base=utc,clock=host \
    -boot order=c,menu=off \
    -object iothread,id=iot0 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$CLOUD_INIT_DIR/OVMF_VARS.fd" \
    -drive file=result/nixos.qcow2,if=none,id=drive0,format=qcow2,cache=writeback,aio=io_uring,discard=unmap,detect-zeroes=unmap \
    -device virtio-blk-pci,drive=drive0,iothread=iot0,num-queues=4 \
    -drive file="$CLOUD_INIT_DIR/seed.iso",media=cdrom \
    -netdev user,id=net0,restrict=off,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${VSCODE_PORT}-:8080,hostfwd=tcp::${TTYD_PORT}-:7681 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -virtfs local,path="$(pwd)",mount_tag=host,security_model=mapped-xattr,multidevs=remap \
    -chardev socket,id=char-nixstore,path="$VIRTIOFS_SOCK" \
    -device vhost-user-fs-pci,chardev=char-nixstore,tag=nixstore \
    -object memory-backend-memfd,id=mem,size=${VM_MEMORY}M,share=on \
    -numa node,memdev=mem \
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

### \_build:vm:wait

Wait for SSH.

```bash {"name":"k9:ci:qcow2:build:_vm-wait","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,duration:slow"}
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

### \_build:vm:sync

Sync source to VM.

```bash {"name":"k9:ci:qcow2:build:_vm-sync","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
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

# Set ownership to kc2:kc2 and restore group-write + setgid on directories.
# git clone creates directories as 755, losing the 2775 that tmpfiles.rules
# sets on /opt/konductor. Without g+ws on directories, kc2 group members
# (additional users like katmorg, dyreddin, etc.) can't create files here
# (e.g., nix build result symlink fails with Permission denied).
ssh $SSH_OPTS kc2admin@localhost 'sudo chown -R kc2:kc2 /opt/konductor && sudo chmod -R a+rX /opt/konductor && sudo fd --type directory --hidden --no-ignore . /opt/konductor --exec chmod g+ws {}'
rm -f "/tmp/${BUNDLE}"

echo "✓ /opt/konductor/${BUNDLE} (bundle)"
echo "✓ /opt/konductor/src/ (cloned)"
```

---

### \_build:vm:rebuild

Run `nixos-rebuild switch` inside VM to build the environment natively.

This ensures:

- Full Konductor environment is built natively inside the VM
- All nix store paths are materialized on disk (via host-store substituter)
- The VM can reproduce itself from /opt/konductor/src

```bash {"name":"k9:ci:qcow2:build:_vm-rebuild","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Generate --override-input flags from vendored input sources.
# /etc/konductor/input-sources.env is baked into the image at build time.
# It maps flake input names to their exact /nix/store paths, which are
# part of the system closure (copied by nixos-install). These paths exist
# on disk from initial image creation — no host mount dependency.
# narHashes match flake.lock exactly → derivation hash match → cache hits.
OVERRIDE_INPUTS=""
if ssh $SSH_OPTS kc2admin@localhost '[ -f /etc/konductor/input-sources.env ]'; then
    echo "Using baked-in input sources from /etc/konductor/input-sources.env..."
    OVERRIDE_INPUTS=$(ssh $SSH_OPTS kc2admin@localhost 'while IFS="=" read -r name spath; do
        [ -n "$name" ] && [ -n "$spath" ] && echo -n " --override-input $name path:$spath"
    done < /etc/konductor/input-sources.env')
elif ssh $SSH_OPTS kc2admin@localhost '[ -d /opt/konductor/src/_sources/nixpkgs ]'; then
    echo "WARNING: No input-sources.env, falling back to path:_sources/ (hash mismatch)..."
    OVERRIDE_INPUTS=$(ssh $SSH_OPTS kc2admin@localhost 'for dir in /opt/konductor/src/_sources/*/; do input=$(basename "$dir"); echo -n " --override-input $input path:/opt/konductor/src/_sources/$input"; done')
fi

# Stop cloud-init services before rebuild to prevent restart failures
# Cloud-init services are oneshot boot services that fail when reactivated
ssh kc2admin@localhost "sudo systemctl stop cloud-config.service cloud-final.service cloud-init-local.service cloud-init.service 2>/dev/null || true"

# Rebuild NixOS from the synced flake
# Use .#konductor (git-clean tree) so derivation hashes match the host build.
# Override-inputs use baked-in store paths from /etc/konductor/input-sources.env,
# ensuring exact narHash match. The host store substituter (local?root=/mnt/host-nix)
# provides build dependencies via read-only virtiofs — nix copies them to local disk.
# nixos-rebuild switch exit codes:
#   0 = success
#   4 = switch succeeded but some units failed to start (transient races, self-healing)
#   other = real failure
REBUILD_RC=0
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nixos-rebuild switch --flake '.#konductor' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || REBUILD_RC=$?
if [ "$REBUILD_RC" -ne 0 ] && [ "$REBUILD_RC" -ne 4 ]; then
    echo "✗ nixos-rebuild failed with exit code $REBUILD_RC"
    exit "$REBUILD_RC"
fi
[ "$REBUILD_RC" -eq 4 ] && echo "⚠ nixos-rebuild switch: some units failed to start (exit 4, non-fatal)"

# Pre-build devshells to cache their closures with proxy support
# This ensures `nix develop` works offline - failures here break offline support
echo "Caching devshells for offline use..."
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link '.#devShells.x86_64-linux.default' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.default failed"; exit 1; }
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link '.#devShells.x86_64-linux.full' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.full failed"; exit 1; }
ssh $SSH_OPTS kc2admin@localhost "cd /opt/konductor/src && source /etc/konductor/proxy.env 2>/dev/null || true && sudo -E env HOME=/root XDG_CACHE_HOME=/root/.cache http_proxy=\${http_proxy:-} https_proxy=\${https_proxy:-} HTTP_PROXY=\${HTTP_PROXY:-} HTTPS_PROXY=\${HTTPS_PROXY:-} NO_PROXY=\${NO_PROXY:-} no_proxy=\${no_proxy:-} nix build --no-link '.#devShells.x86_64-linux.konductor' --no-write-lock-file $OVERRIDE_INPUTS 2>&1" | tee -a "${QCOW2_LOGFILE:-build-vm.log}" || { echo "✗ devShells.konductor failed"; exit 1; }
echo "✓ Devshells cached"

echo "VM rebuilt from /opt/konductor/src flake"
```

---

### \_build:vm:pki:test

Run PKI tests inside VM.

```bash {"name":"k9:ci:qcow2:build:_vm-pki-test","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
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

### \_build:vm:pki:status

Display PKI certificate status.

```bash {"name":"k9:ci:qcow2:build:_vm-pki-status","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "PKI certificate status:"
ssh $SSH_OPTS kc2admin@localhost \
  'PYTHONPATH=/opt/konductor/src/src python3 -m pki status 2>&1' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### \_build:vm:provenance

Write `/.konductor` inside VM.

```bash {"name":"k9:ci:qcow2:build:_vm-provenance","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -eo pipefail

SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP_OPTS="-P $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Build .konductor provenance file locally, then scp to VM.
# All values are gathered, written to a file, and the file is transferred.
# No multi-line bash variables — avoids runme env dump corruption.

# Gather values into short-lived locals (no large/multi-line vars survive to env dump)
_commit=$(git rev-parse HEAD)
_branch=$(git rev-parse --abbrev-ref HEAD)
_remote=$(git remote get-url origin 2>/dev/null || echo ORPHANED)
_dirty=$(git status --porcelain | wc -l | tr -d ' ')
_nix_ver=$(nix --version | head -1)
_nix_hash=$(nix flake metadata --json | jq -r '.locked.narHash')
_nix_drv=$(cat .nix_drv)
_lock_sha=$(sha256sum flake.lock | cut -d' ' -f1)
_build_date=$(date -Iseconds)
_build_host=$(hostname)
_qemu_ver=$(qemu-system-x86_64 --version | head -1 | sed 's/QEMU emulator version //')
_hw_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | tr -d '\n') || _hw_vendor=""
_hw_product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr -d '\n') || _hw_product=""
_hw_serial=$(sudo cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\n') || _hw_serial=""
_oci_image="${CONTAINER_REGISTRY:-registry.docker.arpa}/${CONTAINER_IMAGE:-containercraft/konductor}"

# Build tags array
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
strict = ${KONDUCTOR_STRICT:-false}
oci_image = "$_oci_image"
oci_tags = $_tags
PROVENANCE_EOF

cat .konductor

# Transfer provenance file to VM
scp $SCP_OPTS .konductor kc2admin@localhost:/tmp/.konductor
ssh $SSH_OPTS kc2admin@localhost 'sudo mv /tmp/.konductor /.konductor && sudo chmod 644 /.konductor'

# Regenerate PKI certs with provenance
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki generate --force'
ssh $SSH_OPTS kc2admin@localhost 'sudo PYTHONPATH=/opt/konductor/src/src python3 -m pki bundle'
ssh $SSH_OPTS kc2admin@localhost 'PYTHONPATH=/opt/konductor/src/src python3 -m pki status' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"

# Display system state
ssh $SSH_OPTS kc2admin@localhost 'ff' | tee -a "${QCOW2_LOGFILE:-build-vm.log}"
```

---

### \_build:vm:gc

Garbage collect.

```bash {"name":"k9:ci:qcow2:build:_vm-gc","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -ex
echo "DEBUG gc: HOME=$HOME PATH=$PATH"
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# No overlay — /nix/store is the real on-disk store.
# nixos-rebuild materialized all paths via the host-store substituter.
# Retry up to 3 times in case of transient fd exhaustion.
max_attempts=3
attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
    ssh $SSH_OPTS kc2admin@localhost 'sudo nix-collect-garbage -d' && break
    echo "gc: attempt ${attempt}/${max_attempts} failed, retrying..."
    attempt=$((attempt + 1))
done
ssh $SSH_OPTS kc2admin@localhost 'sudo journalctl --vacuum-size=1M && sudo rm -rf /var/log/journal/* /nix/var/log/nix/drvs/*'
ssh $SSH_OPTS kc2admin@localhost 'sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true'
```

---

### \_build:vm:zero

Zero free space.

```bash {"name":"k9:ci:qcow2:build:_vm-zero","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,duration:slow"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
SSH_PORT="${QCOW2_SSH_PORT:-2222}"
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh $SSH_OPTS kc2admin@localhost 'sudo dd if=/dev/zero of=/zero bs=1M 2>/dev/null || true; sudo rm -f /zero && sync'
```

---

### \_build:vm:halt

Shutdown VM.

```bash {"name":"k9:ci:qcow2:build:_vm-halt","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
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

# Stop virtiofsd daemon (must outlive QEMU, safe to kill after VM halt)
sudo systemctl stop virtiofsd-nixstore 2>/dev/null || true
sudo systemctl reset-failed virtiofsd-nixstore 2>/dev/null || true
sudo rm -f "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}" "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}.pid"
```

---

### \_build:img:clean

Clean credentials from image.

```bash {"name":"k9:ci:qcow2:build:_img-clean","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,requires:guestfs"}
[ "${SKIP_VM_PHASE:-false}" = "true" ] && exit 0
set -e
export LIBGUESTFS_BACKEND=direct
MOUNT="${QCOW2_MOUNT:-/tmp/nixmount}"

sudo mkdir -p "$MOUNT"
sudo guestmount -a result/nixos.qcow2 -m /dev/sda2 "$MOUNT"
trap 'sudo guestunmount "$MOUNT" 2>/dev/null || true; sudo rmdir "$MOUNT" 2>/dev/null || true' EXIT

# Remove host keys, machine identity, cloud-init state, journal logs
sudo rm -f "$MOUNT"/etc/ssh/ssh_host_* "$MOUNT"/etc/machine-id
sudo rm -rf "$MOUNT"/var/lib/cloud "$MOUNT"/var/log/journal/*

# Remove ALL credentials from ALL home directories (root + users)
sudo rm -rf "$MOUNT"/root/.ssh "$MOUNT"/home/*/.ssh 2>/dev/null || true
sudo rm -f "$MOUNT"/root/.gitconfig "$MOUNT"/home/*/.gitconfig 2>/dev/null || true

# Remove build-time cloud-init user account and home directory
# Baked-in users (kc2, kc2admin, runner, forgejo) are declarative in NixOS config.
# The build user (e.g., usrbinkat) was created by cloud-init and must not ship.
BUILD_USER="${USER:-}"
BAKED_IN="kc2 kc2admin runner forgejo"
if [ -n "$BUILD_USER" ]; then
  echo "$BAKED_IN" | grep -qw "$BUILD_USER" || {
    echo "Removing build-time user: $BUILD_USER"
    sudo rm -rf "$MOUNT/home/$BUILD_USER"
    # Remove user entry from passwd and shadow
    for f in passwd shadow; do
      sudo sed -i "/^${BUILD_USER}:/d" "$MOUNT/etc/$f" 2>/dev/null || true
    done
    # Remove user from group membership lists (e.g., wheel, docker, kvm, etc.)
    sudo sed -i "s/,${BUILD_USER}\b//g; s/${BUILD_USER},//g; s/:${BUILD_USER}$/:/" "$MOUNT/etc/group" 2>/dev/null || true
  }
fi

sudo guestunmount "$MOUNT"
trap - EXIT
sync && sleep 1
sudo rmdir "$MOUNT" 2>/dev/null || true
```

---

### \_build:img:compress

ZSTD compress and sparsify image.

Note: SKIP_COMPRESS=true produces a larger, uncompressed image (faster builds, larger output).

```bash {"name":"k9:ci:qcow2:build:_img-compress","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,duration:slow"}
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

### \_build:img:sparsify

Sparsify image (skipped if SKIP_COMPRESS=true).

```bash {"name":"k9:ci:qcow2:build:_img-sparsify","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,duration:slow,requires:guestfs"}
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

### \_build:tmp:clean

Remove temporary files.

```bash {"name":"k9:ci:qcow2:build:_tmp-clean","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image"}
rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"
# Kill virtiofsd if still running (safety net for skipped _build:vm:halt)
sudo systemctl stop virtiofsd-nixstore 2>/dev/null || true
sudo systemctl reset-failed virtiofsd-nixstore 2>/dev/null || true
sudo rm -f "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}" "${QCOW2_VIRTIOFS_SOCK:-/tmp/virtiofsd-nixstore.sock}.pid"
rm -f .nix_drv .system-toplevel
```

---

### \_build:verify

Append post-seal fields to .konductor.

```bash {"name":"k9:ci:qcow2:build:_verify","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,k9:ci:pipeline:image,type:readonly"}
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

### \_build:container

Package QCOW2 as containerDisk.

```bash {"name":"k9:ci:qcow2:build:_container","tag":"k9:ci:qcow2:build,k9:ci:pipeline:all,requires:docker"}
set -e
if ! eval "$(nix print-dev-env .#konductor)"; then
    echo "Warning: nix print-dev-env failed, using current environment"
fi
echo "DEBUG: which docker=$(which docker)"
echo "DEBUG: docker buildx version=$(docker buildx version 2>&1)"
echo "DEBUG: PATH (first 20):" && echo "$PATH" | tr ':' '\n' | head -20 || true
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
TAG="${CONTAINER_TAG:-latest-qcow2}"
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
CONTAINER_TAGS_LINE=$(grep '^oci_tags = ' .konductor | sed 's/^oci_tags = //')
# Extract tags from JSON array: ["tag1", "tag2", ...] -> tag1 tag2 ...
TAGS=$(echo "$CONTAINER_TAGS_LINE" | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$')

echo "Applying tags:"
for tag in $TAGS; do
    if [ "$tag" != "$TAG" ]; then
        docker tag "$FULL_IMAGE" "$REGISTRY/$IMAGE:$tag"
        echo "  ✓ $REGISTRY/$IMAGE:$tag"
    fi
done

echo "✓ Built: $FULL_IMAGE"
```
