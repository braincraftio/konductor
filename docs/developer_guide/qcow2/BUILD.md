---
cwd: ../../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: target:qcow2,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor QCOW2 Build Pipeline

Complete build, validation, and promotion pipeline for airgap-ready NixOS VM images with supply chain attestation.

## Contents

- [Overview](#overview)
- [Pipeline Architecture](#pipeline-architecture)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Workflows](#workflows)
  - [Development Build](#development-build)
  - [Full Pipeline](#full-pipeline)
  - [Validation Only](#validation-only)
  - [Promotion](#promotion)
- [Infrastructure Setup](#infrastructure-setup)
  - [Cluster Management](#cluster-management)
  - [Registry Setup](#registry-setup)
- [Build Tasks](#build-tasks)
- [Validation Tasks](#validation-tasks)
- [Promotion Tasks](#promotion-tasks)
- [Development Tasks](#development-tasks)
- [Output Artifacts](#output-artifacts)
- [Supply Chain Provenance](#supply-chain-provenance)
- [Troubleshooting](#troubleshooting)

---

## Overview

This pipeline builds production-ready QCOW2 VM images with comprehensive supply chain attestation, packages them as KubeVirt containerDisks, validates in a live cluster, and promotes to public registries.

**What this pipeline does:**

1. **Build**: Creates QCOW2 VM image with full Konductor environment pre-installed
2. **Package**: Wraps QCOW2 as OCI containerDisk for KubeVirt
3. **Push**: Publishes to local registry with deterministic tags (git commit, nix derivation)
4. **Validate**: Deploys to KubeVirt cluster, verifies SSH, services, and runner workflows
5. **Promote**: Copies validated image to public registries (docker.io, ghcr.io)

**Key features:**

- **Airgap-ready**: Pre-cached devshells work offline
- **Reproducible**: Nix-based builds with locked dependencies
- **Attestation**: Every artifact tracks git commit, nix derivation, build provenance
- **Self-hosting**: Image can rebuild itself from `/opt/konductor/src`

---

## Pipeline Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  Complete Pipeline: build:qcow2:all                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  BUILD PHASE (delegates to OCI.md)                                           │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ build:qcow2:publish                                        │             │
│  │   ├─ oci:clean      Reset build state                     │             │
│  │   ├─ oci:image      Nix → VM configure → seal             │             │
│  │   ├─ oci:container  Package as containerDisk              │             │
│  │   └─ build:qcow2:push  Multi-tag push to local registry  │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                  │
│  INFRASTRUCTURE PHASE                                                        │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ cluster:up                                                 │             │
│  │   ├─ Start Talos cluster in Docker                        │             │
│  │   └─ Deploy platform (Cilium, cert-manager, registry)     │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                  │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ registry:trust + registry:login                            │             │
│  │   ├─ Install cluster CA for Docker/Skopeo                 │             │
│  │   └─ Authenticate to registry.docker.arpa                 │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                  │
│  VALIDATION PHASE                                                            │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ build:qcow2:validate                                       │             │
│  │   ├─ Deploy VM to KubeVirt                                │             │
│  │   ├─ Verify SSH access                                    │             │
│  │   └─ Test services (ttyd, vscode, restty)                 │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                  │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ build:qcow2:runner-test                                    │             │
│  │   ├─ Push to local Forgejo git server                     │             │
│  │   ├─ Trigger CI workflow                                  │             │
│  │   └─ Verify runner execution                              │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                  │
│  PROMOTION PHASE (manual gate)                                               │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ build:qcow2:promote                                        │             │
│  │   └─ Copy to docker.io / ghcr.io with all tags            │             │
│  └────────────────────────────────────────────────────────────┘             │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Task Delegation:**

- **BUILD.md** (this file): Orchestrates full pipeline, cluster setup, validation, promotion
- **OCI.md**: Core build mechanics (nix, VM, compression, provenance)

---

## Quick Start

### One-Command Full Pipeline

```bash {"name":"quickstart:all","excludeFromRunAll":"true","tag":"type:example"}
# Complete end-to-end: build → cluster → validate → promote
runme run build:qcow2:all
```

### Development Iteration

```bash {"name":"quickstart:dev","excludeFromRunAll":"true","tag":"type:example"}
# Fast iteration: build + push only (no cluster/validation)
runme run build:qcow2:publish

# Interactive development: boot VM for testing
runme run build:qcow2:start
runme run build:qcow2:ssh
runme run build:qcow2:stop
```

### Validation Only

```bash {"name":"quickstart:validate","excludeFromRunAll":"true","tag":"type:example"}
# Validate existing image in cluster
runme run build:qcow2:validate
runme run build:qcow2:validate-services
runme run build:qcow2:runner-test
```

### Promotion

```bash {"name":"quickstart:promote","excludeFromRunAll":"true","tag":"type:example"}
# Copy validated image to public registry
export DOCKER_TOKEN="<your-token>"
runme run build:qcow2:promote
```

---

## Task Reference

Quick reference for all available tasks. Click task names to jump to detailed documentation.

### Build Tasks

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`build:qcow2:publish`](#buildqcow2publish) | Full build pipeline: clean → image → container → push | 30-60 min | nix, kvm |
| [`build:qcow2:image`](#buildqcow2image) | Build QCOW2 image (delegates to oci:image) | 30-60 min | nix, kvm |
| [`build:qcow2:container`](#buildqcow2container) | Package QCOW2 as containerDisk | 1-2 min | docker |
| [`build:qcow2:push`](#buildqcow2push) | Push to registry with multi-tag | 1-2 min | docker, skopeo |
| [`build:qcow2:clean`](#buildqcow2clean) | Reset build state | <1 min | - |

### Infrastructure Tasks

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`cluster:up`](#clusterup) | Start Talos + deploy platform | 5-10 min | docker, kubectl |
| [`cluster:down`](#clusterdown) | Destroy cluster | 1-2 min | kubectl |
| [`cluster:status`](#clusterstatus) | Check cluster health | <1 min | kubectl |
| [`registry:trust`](#registrytrust) | Install cluster CA | <1 min | kubectl |
| [`registry:login`](#registrylogin) | Authenticate to registry | <1 min | docker, skopeo |
| [`registry:list`](#registrylist) | List images in registry | <1 min | curl |
| [`registry:tags`](#registrytags) | List tags for konductor image | <1 min | curl |

### Validation Tasks

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`build:qcow2:validate`](#buildqcow2validate) | Deploy to KubeVirt + SSH test | 3-5 min | kubectl, virtctl |
| [`build:qcow2:validate-services`](#buildqcow2validate-services) | Test web terminals (non-blocking) | 1-2 min | kubectl, virtctl |
| [`build:qcow2:runner-test`](#buildqcow2runner-test) | Forgejo runner workflow test | 5-10 min | kubectl, git |

### Promotion Tasks

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`build:qcow2:promote`](#buildqcow2promote) | Copy to public registry | 2-5 min | skopeo, auth |

### Development Tasks

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`build:qcow2:start`](#buildqcow2start) | Boot VM for development | 2-3 min | qemu, kvm |
| [`build:qcow2:ssh`](#buildqcow2ssh) | SSH into running VM | instant | ssh |
| [`build:qcow2:stop`](#buildqcow2stop) | Shutdown VM | <1 min | - |
| [`build:qcow2:rebase`](#buildqcow2rebase) | Rebuild NixOS host from flake | 5-10 min | nixos |

### Complete Pipeline

| Task | Description | Duration | Dependencies |
|------|-------------|----------|--------------|
| [`build:qcow2:all`](#buildqcow2all) | Full end-to-end pipeline | 60-90 min | all |

---

## Workflows

### Development Build

Fast iteration cycle for development.

```text
┌────────────────────────────────────────┐
│ Development Workflow                   │
├────────────────────────────────────────┤
│ 1. build:qcow2:publish                 │
│    └─ Build + package + push           │
│                                        │
│ 2. (optional) build:qcow2:start        │
│    └─ Boot VM for interactive testing  │
└────────────────────────────────────────┘
```

**Use case:** Iterating on flake changes, testing builds locally.

```bash {"name":"workflow:dev","excludeFromRunAll":"true","tag":"type:example"}
# Build and push to local registry
runme run build:qcow2:publish

# Optional: boot VM for testing
runme run build:qcow2:start
ssh -p 2222 kc2admin@localhost
runme run build:qcow2:stop
```

---

### Full Pipeline

Complete end-to-end with cluster validation.

```text
┌────────────────────────────────────────┐
│ Full Pipeline Workflow                 │
├────────────────────────────────────────┤
│ 1. build:qcow2:publish                 │
│ 2. cluster:up                          │
│ 3. registry:trust + registry:login     │
│ 4. build:qcow2:validate                │
│ 5. build:qcow2:runner-test             │
│ 6. build:qcow2:promote                 │
└────────────────────────────────────────┘
```

**Use case:** Release builds, CI/CD pipelines.

```bash {"name":"workflow:full","excludeFromRunAll":"true","tag":"type:example"}
# One command runs entire pipeline
runme run build:qcow2:all
```

---

### Validation Only

Validate existing image without rebuilding.

```text
┌────────────────────────────────────────┐
│ Validation Workflow                    │
├────────────────────────────────────────┤
│ Prerequisites: cluster running, image  │
│                already pushed           │
│                                        │
│ 1. build:qcow2:validate                │
│ 2. build:qcow2:validate-services       │
│ 3. build:qcow2:runner-test             │
└────────────────────────────────────────┘
```

**Use case:** Testing existing image, debugging cluster issues.

```bash {"name":"workflow:validate","excludeFromRunAll":"true","tag":"type:example"}
# Validate existing image
runme run build:qcow2:validate
runme run build:qcow2:validate-services
runme run build:qcow2:runner-test
```

---

### Promotion

Promote validated image to public registry.

```text
┌────────────────────────────────────────┐
│ Promotion Workflow                     │
├────────────────────────────────────────┤
│ Prerequisites: validation passed       │
│                                        │
│ 1. Set credentials (DOCKER_TOKEN)     │
│ 2. build:qcow2:promote                 │
└────────────────────────────────────────┘
```

**Use case:** Publishing releases to docker.io or ghcr.io.

```bash {"name":"workflow:promote","excludeFromRunAll":"true","tag":"type:example"}
# Set credentials
export DOCKER_TOKEN="<your-docker-hub-token>"

# Promote to docker.io
runme run build:qcow2:promote

# Or promote to ghcr.io
export GITHUB_TOKEN="<your-github-token>"
export PROMOTE_REGISTRY="ghcr.io"
export PROMOTE_IMAGE="your-org/konductor"
runme run build:qcow2:promote
```

---

## Infrastructure Setup

### Cluster Management

#### cluster:up

Start Talos Kubernetes cluster in Docker and deploy platform services.

**What it does:**

1. Starts Talos control plane + worker nodes in Docker containers
2. Deploys core platform via Pulumi:
   - Cilium CNI
   - cert-manager (TLS certificate management)
   - Envoy Gateway (ingress)
   - Zot registry (local OCI registry at registry.docker.arpa)
   - KubeVirt (VM orchestration)
   - Forgejo (git server + runner for CI testing)

**Prerequisites:** Docker running, sufficient resources (8GB RAM, 100GB disk)

```sh {"name":"cluster:up","excludeFromRunAll":"true","tag":"type:entry,scope:cluster,duration:slow"}
# Clean any existing cluster
mise run dev:k8s:compose:clean

# Start Talos in Docker
mise run dev:k8s:compose:up

# Deploy platform (Cilium, cert-manager, Envoy Gateway, Zot registry, etc.)
mise run dev:k8s:pulumi:up
```

---

#### cluster:down

Destroy the cluster.

**Warning:** This is destructive. All cluster data will be lost.

```sh {"name":"cluster:down","excludeFromRunAll":"true","tag":"type:entry,type:destructive,scope:cluster"}
mise run dev:k8s:compose:clean
```

---

#### cluster:status

Check cluster and registry status.

```sh {"name":"cluster:status","excludeFromRunAll":"true","tag":"type:entry,scope:cluster,type:readonly"}
kubectl get nodes
kubectl get po -n registry
kubectl get httproute -n registry
curl -sk -u admin:admin https://registry.docker.arpa/v2/_catalog | jq
```

---

### Registry Setup

#### registry:trust

Install cluster CA certificate for Docker daemon and Skopeo.

**What it does:**

1. Extracts CA certificate from Envoy Gateway TLS secret
2. Installs to `/etc/docker/certs.d/registry.docker.arpa/ca.crt` (Docker daemon)
3. Installs to `${WORKSPACE_ROOT}/.certs/registry.docker.arpa/ca.crt` (Skopeo)

**Why needed:** `registry.docker.arpa` uses a self-signed CA from cert-manager. Docker and Skopeo need this CA to trust the registry's TLS certificate.

**Prerequisites:** Cluster running, kubectl configured

```sh {"name":"registry:trust","excludeFromRunAll":"true","tag":"type:entry,scope:registry"}
set -e

[[ "${WORKSPACE_ROOT:-}" == /* ]] && printf "✓ WORKSPACE_ROOT=%s\n" "$WORKSPACE_ROOT" || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

export KUBECONFIG="${WORKSPACE_ROOT}/.config/talos/clusters/docker-dev/generated/kubeconfig"
printf "✓ KUBECONFIG=%s\n" "$KUBECONFIG"
[ -f "$KUBECONFIG" ] && printf "✓ KUBECONFIG file exists\n" || { echo "✗ KUBECONFIG file not found"; exit 1; }

REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
K8S_CONTEXT="${KUBECTL_CONTEXT:-admin@docker-dev-host}"

# Docker daemon cert directory
DOCKER_CERT_DIR="/etc/docker/certs.d/$REGISTRY"
sudo mkdir -p "$DOCKER_CERT_DIR"

kubectl --context "$K8S_CONTEXT" \
    get secret gateway-tls-https -n envoy-gateway-system \
    -o jsonpath='{.data.ca\.crt}' | base64 -d \
    | sudo tee "$DOCKER_CERT_DIR/ca.crt" > /dev/null

echo "✓ CA installed: $DOCKER_CERT_DIR/ca.crt"

# Skopeo/Podman cert directory
CONTAINERS_CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"
mkdir -p "$CONTAINERS_CERT_DIR"
kubectl --context "$K8S_CONTEXT" \
    get secret gateway-tls-https -n envoy-gateway-system \
    -o jsonpath='{.data.ca\.crt}' | base64 -d \
    > "$CONTAINERS_CERT_DIR/ca.crt"

echo "✓ CA installed: $CONTAINERS_CERT_DIR/ca.crt"
```

---

#### registry:login

Authenticate Docker and Skopeo to registry.

**Credentials:** Default `admin:admin` (configurable via `REGISTRY_USERNAME`/`REGISTRY_PASSWORD`)

```sh {"name":"registry:login","excludeFromRunAll":"true","tag":"type:entry,scope:registry"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
USERNAME="${REGISTRY_USERNAME:-admin}"
PASSWORD="${REGISTRY_PASSWORD:-admin}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"

# Docker login
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

# Skopeo login
echo "$PASSWORD" | skopeo login "$REGISTRY" \
    --username "$USERNAME" --password-stdin \
    --cert-dir "$CERT_DIR" --compat-auth-file ${WORKSPACE_ROOT}/.docker/config.json

echo "✓ Logged in to $REGISTRY"
```

---

#### registry:list

List images in registry.

```sh {"name":"registry:list","excludeFromRunAll":"true","tag":"type:entry,scope:registry,type:readonly"}
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
curl -sk -u "${REGISTRY_USERNAME:-admin}:${REGISTRY_PASSWORD:-admin}" \
    "https://$REGISTRY/v2/_catalog" | jq
```

---

#### registry:tags

List tags for konductor image.

```sh {"name":"registry:tags","excludeFromRunAll":"true","tag":"type:entry,scope:registry,type:readonly"}
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
curl -sk -u "${REGISTRY_USERNAME:-admin}:${REGISTRY_PASSWORD:-admin}" \
    "https://$REGISTRY/v2/$IMAGE/tags/list" | jq
```

---

## Build Tasks

### build:qcow2:publish

Full build pipeline: clean → image → container → push.

**What it does:**

1. Delegates to `oci:build` (from OCI.md) for core build:
   - `oci:clean` - Reset build state
   - `oci:image` - Build QCOW2 image (nix → VM → seal)
   - `oci:container` - Package as containerDisk
2. Pushes to local registry with multi-tag

**Output:**

- `konductor.qcow2` - Compressed QCOW2 image
- `.konductor` - Provenance file
- OCI image at `registry.docker.arpa/containercraft/konductor:latest-qcow2`

**Duration:** 30-60 minutes (depends on build host)

**Skip flags:**

- `SKIP_NIX_BUILD=true` - Reuse existing nix build
- `SKIP_VM_PHASE=true` - Reuse existing image (skip VM configure)
- `SKIP_COMPRESS=true` - Skip ZSTD compression (faster, larger image)

```sh {"name":"build:qcow2:publish","excludeFromRunAll":"true","tag":"type:entry,duration:slow"}
set -e
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  build:qcow2:publish - Build + Package + Push Pipeline"
echo "═══════════════════════════════════════════════════════════════════════════"

echo ""
echo "▶ Phase 1: Build QCOW2 + containerDisk (oci:build)..."
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:build

echo ""
echo "▶ Phase 2: Push to registry..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" build:qcow2:push

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ Build complete!"
echo "═══════════════════════════════════════════════════════════════════════════"
cat .konductor
```

---

### build:qcow2:image

Build QCOW2 image (delegates to `oci:image` from OCI.md).

**Use case:** Build image only, no containerDisk packaging.

```sh {"name":"build:qcow2:image","excludeFromRunAll":"true","tag":"type:entry,duration:slow"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:image
```

---

### build:qcow2:container

Package QCOW2 as containerDisk (delegates to `oci:container` from OCI.md).

**Prerequisites:** `konductor.qcow2` exists (run `build:qcow2:image` first)

```sh {"name":"build:qcow2:container","excludeFromRunAll":"true","tag":"type:entry,requires:docker"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:container
```

---

### build:qcow2:push

Push container with multi-tag (git commit, nix derivation, latest).

**Tags applied:**

- `latest-qcow2` - Convenience tag (always latest)
- `qcow2-<git-commit>` - Source traceability (only if tree is clean)
- `qcow2-<nix-drv>` - Reproducible build ID

**Prerequisites:** Container image built (`build:qcow2:container`), registry trust configured

```sh {"name":"build:qcow2:push","excludeFromRunAll":"true","tag":"type:entry,requires:docker"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
BASE_TAG="${CONTAINER_TAG:-latest-qcow2}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

# Build tag list
TAGS=("$BASE_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("qcow2-${git_commit}")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("qcow2-${nix_drv}")
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

echo "Pushed: $REGISTRY/$IMAGE"
printf "  %s\n" "${TAGS[@]}"
echo "Digest: $OCI_DIGEST"
```

---

### build:qcow2:clean

Reset build state (delegates to `oci:clean` from OCI.md).

**What it cleans:**

- Build artifacts: `result/`, `konductor.qcow2`, `.konductor`
- VM runtime: PID file, log file, cloud-init ISO
- Mounts: `/tmp/nixmount` (guestfs)

```sh {"name":"build:qcow2:clean","excludeFromRunAll":"true","tag":"type:entry,type:destructive"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" oci:clean
```

---

## Validation Tasks

### build:qcow2:validate

Deploy VM to KubeVirt and validate SSH access.

**What it does:**

1. Deploys VM to `konductor` namespace via Pulumi (`mise run dev:k8s:konductor:up`)
2. Waits for VM to boot and SSH to be available
3. Verifies provenance file `/.konductor` exists
4. Runs basic validation commands

**Prerequisites:** Cluster running, image pushed to registry

**Duration:** 3-5 minutes

```sh {"name":"build:qcow2:validate","excludeFromRunAll":"true","tag":"type:entry,scope:validation,requires:k8s,duration:slow"}
set -e
mise run dev:k8s:konductor:up
mise run dev:k8s:konductor:validate
```

---

### build:qcow2:validate-services

Test web terminal services via port-forward (non-blocking).

**Services tested:**

- `ttyd` (port 7681) - xterm.js terminal (readonly)
- `ghostty-web` (port 7682) - ghostty WASM terminal (readonly)
- `ttyd-rw` (port 7683) - xterm.js terminal (writable)
- `ghostty-web-rw` (port 7684) - ghostty WASM terminal (writable)

**Note:** This check is non-blocking. Failures generate warnings but don't fail the pipeline. Services may still be starting.

**Prerequisites:** VM deployed to KubeVirt (`build:qcow2:validate`)

```sh {"name":"build:qcow2:validate-services","excludeFromRunAll":"true","tag":"type:entry,scope:validation,requires:k8s"}
set -eo pipefail

pkill -f "virtctl port-forward.*konductor" 2>/dev/null || true

cleanup() {
    pkill -f "virtctl port-forward.*konductor" 2>/dev/null || true
}
trap cleanup EXIT

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  build:qcow2:validate-services - Web Terminal Health Check"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Services:"
echo "    ttyd readonly     (7681) - xterm.js terminal"
echo "    ghostty-web readonly (7682) - ghostty WASM terminal"
echo "    ttyd writable     (7683) - xterm.js terminal (rw)"
echo "    ghostty-web writable (7684) - ghostty WASM terminal (rw)"
echo ""
echo "  Note: This check is non-blocking. Failures are warnings only."
echo ""

NAMESPACE="konductor"
VMI="vmi/konductor"
WARNINGS=0

SERVICES=(
    "ttyd:7681:<!DOCTYPE html>"
    "ghostty-web:7682:<!DOCTYPE html>"
    "ttyd-rw:7683:<!DOCTYPE html>"
    "ghostty-web-rw:7684:<!DOCTYPE html>"
)

for svc in "${SERVICES[@]}"; do
    IFS=':' read -r name port expected <<< "$svc"
    echo "▶ Testing ${name} (port ${port})..."

    virtctl port-forward --namespace="$NAMESPACE" "$VMI" "${port}:${port}" &
    PF_PID=$!
    sleep 2

    if curl -sf --max-time 5 "http://localhost:${port}/" 2>/dev/null | grep -q "$expected"; then
        echo "  ✓ ${name}: responding with expected content"
    else
        echo "  ⚠ ${name}: not responding or unexpected content"
        ((WARNINGS++)) || true
    fi

    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
done

echo ""
if [ "$WARNINGS" -eq 0 ]; then
    echo "✅ All services responding"
else
    echo "⚠ ${WARNINGS} service(s) not responding (non-blocking)"
    echo "  Manual verification:"
    echo "  virtctl port-forward -n konductor vmi/konductor 7681:7681 7682:7682 7683:7683 7684:7684"
fi
```

---

### build:qcow2:runner-test

Test Forgejo runner by pushing to local git server and validating workflow execution.

**What it does:**

1. Provisions Forgejo user and access token
2. Creates repositories: `braincraft/k9` (main repo) and `braincraft/workspace` (shared tooling)
3. Pushes workspace repository
4. Pushes k9 repository
5. Triggers workflow via API: `validate-environment.yaml`
6. Polls workflow status until completion
7. Verifies success

**Why important:** This validates that:

- Forgejo runner can execute workflows in the VM
- VM has network access to pull dependencies
- Workspace pattern works (runner clones workspace repo first)
- Build environment is functional

**Prerequisites:** Cluster running with Forgejo deployed, VM with runner configured

**Duration:** 5-10 minutes

```sh {"name":"build:qcow2:runner-test","excludeFromRunAll":"true","tag":"type:entry,scope:validation,requires:k8s,duration:slow"}
set -eo pipefail

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  build:qcow2:runner-test - Validate Forgejo Runner"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

[[ "${WORKSPACE_ROOT:-}" == /* ]] || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

export KUBECONFIG="${WORKSPACE_ROOT}/.config/talos/clusters/docker-dev/generated/kubeconfig"
[ -f "$KUBECONFIG" ] || { echo "✗ KUBECONFIG not found"; exit 1; }

FORGEJO_NS="forgejo"
FORGEJO_DEPLOY="deployment/forgejo-deployment"
REPO_NAME="k9"
REPO_OWNER="braincraft"
TOKEN_NAME="ci-runner-test-$(date +%s)"
BRANCH="${GITHUB_REF_NAME:-main}"
WORKFLOW="validate-environment.yaml"

echo "▶ Phase 1: Provision Forgejo credentials..."
RUNNER_PASSWORD="${FORGEJO_RUNNER_PASSWORD:-admin123}"

TOKEN_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  forgejo admin user generate-access-token \
    --username "$REPO_OWNER" \
    --token-name "$TOKEN_NAME" \
    --scopes "all" \
    --raw 2>&1) && TOKEN="$TOKEN_OUTPUT" || true

if [ -z "$TOKEN" ]; then
  CREATE_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
    forgejo admin user create \
      --username "$REPO_OWNER" \
      --email "${REPO_OWNER}@localhost" \
      --password "$RUNNER_PASSWORD" \
      --admin \
      --must-change-password=false \
      --access-token \
      --access-token-name "$TOKEN_NAME" \
      --access-token-scopes "all" 2>&1) || true
  TOKEN=$(echo "$CREATE_OUTPUT" | rg -o '[a-f0-9]{40}' | tail -1)

  if [ -z "$TOKEN" ] && echo "$CREATE_OUTPUT" | grep -q "already exists"; then
    RETRY_TOKEN_NAME="${TOKEN_NAME}-$(date +%s)"
    TOKEN_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
      forgejo admin user generate-access-token \
        --username "$REPO_OWNER" \
        --token-name "$RETRY_TOKEN_NAME" \
        --scopes "all" \
        --raw 2>&1) && TOKEN="$TOKEN_OUTPUT" || true
  fi
fi

[ -n "$TOKEN" ] || { echo "✗ Failed to provision credentials"; exit 1; }
echo "✓ Credentials provisioned"

echo ""
echo "▶ Phase 2: Create repositories..."
kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    --post-data="{\"name\":\"$REPO_NAME\",\"private\":false}" \
    "http://localhost:3000/api/v1/user/repos" 2>&1 || true

kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    --post-data="{\"name\":\"workspace\",\"private\":false}" \
    "http://localhost:3000/api/v1/user/repos" 2>&1 || true

echo ""
echo "▶ Phase 3-4: Push repositories..."
GIT_CA_CERT="${WORKSPACE_ROOT}/.certs/registry.docker.arpa/ca.crt"
[ -f "$GIT_CA_CERT" ] || { echo "✗ CA cert not found"; exit 1; }

git -C .. remote remove runner-test 2>/dev/null || true
git -C .. remote add runner-test "https://${REPO_OWNER}:${TOKEN}@git.docker.arpa/${REPO_OWNER}/workspace.git"
GIT_SSL_CAINFO="$GIT_CA_CERT" git -C .. push --force runner-test "HEAD:refs/heads/$BRANCH" 2>&1 || true
git -C .. remote remove runner-test 2>/dev/null || true

git remote remove runner-test 2>/dev/null || true
git remote add runner-test "https://${REPO_OWNER}:${TOKEN}@git.docker.arpa/${REPO_OWNER}/${REPO_NAME}.git"
GIT_SSL_CAINFO="$GIT_CA_CERT" git push --force runner-test "HEAD:refs/heads/$BRANCH" 2>&1 || true

echo ""
echo "▶ Phase 5: Trigger workflow..."
kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- --post-data='{"ref":"'"$BRANCH"'"}' \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    "http://localhost:3000/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/${WORKFLOW}/dispatches" 2>&1 || true

echo ""
echo "▶ Phase 6: Wait for workflow completion..."
MAX_WAIT=300
POLL_INTERVAL=5
ELAPSED=0
STATUS="unknown"
sleep 3

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  RUN_JSON=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
    wget -qO- --header="Authorization: token $TOKEN" \
      "http://localhost:3000/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs" 2>/dev/null) || true

  if [ -n "$RUN_JSON" ]; then
    RUN_LINE=$(echo "$RUN_JSON" | jq -r ".workflow_runs[] | select(.workflow_id == \"$WORKFLOW\") | \"\(.id) \(.status) \(.html_url)\"" | sort -n | tail -1)
    if [ -n "$RUN_LINE" ]; then
      STATUS=$(echo "$RUN_LINE" | cut -d' ' -f2)
      echo "  Status: ${STATUS} (${ELAPSED}s)"
      case "$STATUS" in success|failure|cancelled|skipped) break ;; esac
    fi
  fi
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

git remote remove runner-test 2>/dev/null || true

case "$STATUS" in
  success) echo "✓ Workflow completed successfully" ;;
  *) echo "✗ Workflow failed or timed out"; exit 1 ;;
esac
```

---

## Promotion Tasks

### build:qcow2:promote

Copy validated image to public registry (docker.io or ghcr.io).

**What it does:**

1. Verifies source image exists in local registry
2. Authenticates to destination registry
3. Copies image with all tags (latest, git commit, nix derivation)
4. Verifies copy with digest check

**Authentication:**

- **docker.io**: Set `DOCKER_TOKEN` environment variable (from Docker Hub)
- **ghcr.io**: Set `GITHUB_TOKEN` environment variable (GitHub PAT with packages:write)

**Environment variables:**

- `PROMOTE_REGISTRY` - Destination registry (default: `docker.io`)
- `PROMOTE_IMAGE` - Destination image (default: `containercraft/konductor`)
- `PROMOTE_TAG` - Base tag (default: `latest-qcow2`)
- `DOCKER_TOKEN` - Docker Hub access token
- `DOCKER_USERNAME` - Docker Hub username (default: `containercraft`)
- `GITHUB_TOKEN` - GitHub personal access token
- `GITHUB_ACTOR` - GitHub username

**Prerequisites:** Image validated (`build:qcow2:validate` passed), credentials configured

**Duration:** 2-5 minutes

```sh {"name":"build:qcow2:promote","excludeFromRunAll":"true","tag":"type:entry,scope:promotion,duration:slow"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  build:qcow2:promote - Promote to Public Registry"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

[[ "${WORKSPACE_ROOT:-}" == /* ]] || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

PROVENANCE_FILE="${WORKSPACE_ROOT}/k9/.konductor"
[ -f "$PROVENANCE_FILE" ] || { echo "✗ Provenance file not found"; exit 1; }

SRC_REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
SRC_IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
SRC_TAG="${CONTAINER_TAG:-latest-qcow2}"
SRC_CERT_DIR="${WORKSPACE_ROOT}/.certs/${SRC_REGISTRY}"
[ -d "$SRC_CERT_DIR" ] || { echo "✗ Source cert dir not found"; exit 1; }

DST_REGISTRY="${PROMOTE_REGISTRY:-docker.io}"
DST_IMAGE="${PROMOTE_IMAGE:-containercraft/konductor}"
DST_TAG="${PROMOTE_TAG:-latest-qcow2}"

echo "Source: ${SRC_REGISTRY}/${SRC_IMAGE}:${SRC_TAG}"
echo "Destination: ${DST_REGISTRY}/${DST_IMAGE}:${DST_TAG}"
echo ""

# Authentication
AUTH_LOCATIONS=("${WORKSPACE_ROOT}/.docker/config.json" "${HOME}/.docker/config.json")
DEST_AUTH_FILE=""

has_docker_io_creds() {
    [[ -f "$1" ]] && jq -e '.auths["https://index.docker.io/v1/"]' "$1" &>/dev/null
}
has_ghcr_creds() {
    [[ -f "$1" ]] && jq -e '.auths["ghcr.io"]' "$1" &>/dev/null
}

for auth_file in "${AUTH_LOCATIONS[@]}"; do
    [[ ! -f "$auth_file" ]] && continue
    if [[ "$DST_REGISTRY" == "docker.io" ]] && has_docker_io_creds "$auth_file"; then
        DEST_AUTH_FILE="$auth_file"
        break
    elif [[ "$DST_REGISTRY" == "ghcr.io" ]] && has_ghcr_creds "$auth_file"; then
        DEST_AUTH_FILE="$auth_file"
        break
    fi
done

[[ -z "$DEST_AUTH_FILE" ]] && DEST_AUTH_FILE="${WORKSPACE_ROOT}/.docker/config.json"

if [[ "$DST_REGISTRY" == "docker.io" ]]; then
    if [[ -n "${DOCKER_TOKEN:-}" ]]; then
        mkdir -p "$(dirname "$DEST_AUTH_FILE")"
        echo "$DOCKER_TOKEN" | skopeo login docker.io -u "${DOCKER_USERNAME:-containercraft}" --password-stdin --compat-auth-file "$DEST_AUTH_FILE"
        echo "✓ Authenticated to docker.io"
    elif has_docker_io_creds "$DEST_AUTH_FILE"; then
        echo "✓ Using existing docker.io credentials"
    else
        echo "✗ No authentication. Set DOCKER_TOKEN or run: docker login docker.io"
        exit 1
    fi
elif [[ "$DST_REGISTRY" == "ghcr.io" ]]; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        mkdir -p "$(dirname "$DEST_AUTH_FILE")"
        echo "$GITHUB_TOKEN" | skopeo login ghcr.io -u "${GITHUB_ACTOR:-github}" --password-stdin --compat-auth-file "$DEST_AUTH_FILE"
        echo "✓ Authenticated to ghcr.io"
    elif has_ghcr_creds "$DEST_AUTH_FILE"; then
        echo "✓ Using existing ghcr.io credentials"
    else
        echo "✗ No authentication. Set GITHUB_TOKEN or run: docker login ghcr.io"
        exit 1
    fi
fi

# Verify source
skopeo inspect --cert-dir "$SRC_CERT_DIR" docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" &>/dev/null \
    || { echo "✗ Source image not found"; exit 1; }
echo "✓ Source exists"

# Read provenance for tags
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' "$PROVENANCE_FILE")
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' "$PROVENANCE_FILE")
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' "$PROVENANCE_FILE")

TAGS=("$DST_TAG")
[ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && TAGS+=("qcow2-${git_commit}")
[ -n "$nix_drv" ] && TAGS+=("qcow2-${nix_drv}")

echo ""
echo "Copying with tags:"
printf "  %s\n" "${TAGS[@]}"
echo ""

for tag in "${TAGS[@]}"; do
    echo "▶ ${DST_REGISTRY}/${DST_IMAGE}:${tag}"
    skopeo copy \
        --src-cert-dir "$SRC_CERT_DIR" \
        --dest-authfile "$DEST_AUTH_FILE" \
        docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" \
        docker://"$DST_REGISTRY/$DST_IMAGE:$tag"
done

echo ""
echo "✓ Promoted to ${DST_REGISTRY}/${DST_IMAGE}"
skopeo inspect --no-creds docker://"$DST_REGISTRY/$DST_IMAGE:$DST_TAG" | jq '{Digest, Created}'
```

---

## Development Tasks

### build:qcow2:start

Boot VM for local development and testing.

**What it does:**

1. Cleans any existing VM runtime state
2. Generates cloud-init ISO
3. Boots QCOW2 image with QEMU
4. Waits for SSH to be available

**Port forwarding:**

- SSH: localhost:2222 → VM:22 (configurable via `QCOW2_SSH_PORT`)
- VS Code: localhost:18080 → VM:8080 (configurable via `QCOW2_VSCODE_PORT`)
- TTYD: localhost:17681 → VM:7681 (configurable via `QCOW2_TTYD_PORT`)

**Prerequisites:** `result/nixos.qcow2` exists (run `build:qcow2:image` first)

```sh {"name":"build:qcow2:start","excludeFromRunAll":"true","tag":"type:entry,scope:dev,requires:kvm"}
set -e
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
PIDFILE="${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. Use: ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
    exit 0
fi

[ -f result/nixos.qcow2 ] || { echo "No image. Run build:qcow2:image first."; exit 1; }

# Clean VM runtime state only
(pgrep -f "[q]emu-system.*nixos.qcow2" && pkill -9 -f "[q]emu-system.*nixos.qcow2") || true
rm -f "${QCOW2_PIDFILE:-/tmp/konductor-build-vm.pid}" "${QCOW2_LOGFILE:-build-vm.log}"
sudo rm -rf "${QCOW2_CLOUD_INIT_DIR:-/tmp/konductor-build-cloud-init}"

runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:cloudinit
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:boot
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:wait

echo "VM ready:"
echo "  SSH:     ssh -p ${QCOW2_SSH_PORT:-2222} kc2admin@localhost"
echo "  VS Code: http://localhost:${QCOW2_VSCODE_PORT:-18080}"
echo "  TTYD:    http://localhost:${QCOW2_TTYD_PORT:-17681}"
```

---

### build:qcow2:ssh

SSH into running VM.

**Default port:** 2222 (configurable via `QCOW2_SSH_PORT`)

```sh {"name":"build:qcow2:ssh","excludeFromRunAll":"true","tag":"type:entry,scope:dev,interactive:true"}
ssh -p "${QCOW2_SSH_PORT:-2222}" kc2admin@localhost
```

---

### build:qcow2:stop

Gracefully shutdown running VM.

```sh {"name":"build:qcow2:stop","excludeFromRunAll":"true","tag":"type:entry,scope:dev"}
OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"
runme run --direnv=true --load-env=false --filename "$OCI_BUILD_FILE" _oci:vm:halt
```

---

### build:qcow2:rebase

Rebuild NixOS host from flake (dogfooding).

**Use case:** Testing flake changes on the build host itself.

**Warning:** This rebuilds the NixOS system running the build. Only use on NixOS hosts.

```sh {"name":"build:qcow2:rebase","excludeFromRunAll":"true","tag":"type:entry,scope:dev,requires:nixos"}
set -e
sudo nixos-rebuild switch --flake .#konductor
echo "✓ NixOS rebuilt. Run 'direnv reload' to pick up environment changes."
```

---

## Complete Pipeline

### build:qcow2:all

Complete end-to-end pipeline with validation.

**Pipeline stages:**

1. **Build**: `build:qcow2:publish` - Build + package + push
2. **Infrastructure**: `cluster:up` - Start Talos + deploy platform
3. **Trust**: `registry:trust` - Install cluster CA
4. **Validation**: `build:qcow2:validate` - Deploy to KubeVirt + SSH test
5. **Runner Test**: `build:qcow2:runner-test` - Forgejo workflow validation
6. **Verification**: `registry:tags` - Verify pushed tags

**Note:** Promotion (`build:qcow2:promote`) is NOT included. It's a manual gate after validation passes.

**Duration:** 60-90 minutes

**Prerequisites:** Docker running, sufficient resources (8GB RAM, 100GB disk)

```sh {"name":"build:qcow2:all","excludeFromRunAll":"true","tag":"type:entry,duration:very-slow"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  build:qcow2:all - Complete End-to-End Pipeline"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Pipeline stages:"
echo "    1. Build + package + push"
echo "    2. Start cluster + deploy platform"
echo "    3. Install cluster CA"
echo "    4. Deploy to KubeVirt + validate"
echo "    5. Test Forgejo runner workflow"
echo "    6. Verify tags"
echo ""
echo "  Duration: 60-90 minutes"
echo "  Prerequisites: Docker, 8GB RAM, 100GB disk"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"

echo ""
echo "▶ Phase 1: Build + package + push..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" build:qcow2:publish

echo ""
echo "▶ Phase 2: Start cluster + deploy platform..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" cluster:up

echo ""
echo "▶ Phase 3: Install cluster CA..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" registry:trust

echo ""
echo "▶ Phase 4: Verify pushed tags..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" registry:tags

echo ""
echo "▶ Phase 5: Deploy to KubeVirt + validate..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" build:qcow2:validate

echo ""
echo "▶ Phase 6: Test Forgejo runner workflow..."
runme run --direnv=true --load-env=false --filename "$QCOW2_BUILD_FILE" build:qcow2:runner-test

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✅ Pipeline complete! Image validated and ready for promotion."
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Review validation results above"
echo "  2. Set credentials: export DOCKER_TOKEN=<your-token>"
echo "  3. Promote: runme run build:qcow2:promote"
echo ""
cat .konductor
```

---

## Output Artifacts

### QCOW2 Image

**Path:** `konductor.qcow2`

**Format:** QCOW2 with ZSTD compression

**Size:** ~4GB (compressed), ~20GB (uncompressed)

**Contents:**

- NixOS 24.11
- Full Konductor environment (devshells pre-cached)
- Source code: `/opt/konductor/src/` (git repository)
- Bundle: `/opt/konductor/k9-<commit>.bundle` (portable git archive)
- Provenance: `/.konductor` (TOML format)

### OCI Container

**Registry:** `registry.docker.arpa/containercraft/konductor`

**Tags:**

- `latest-qcow2` - Latest build
- `qcow2-<git-commit>` - Source traceability (40-char SHA)
- `qcow2-<nix-drv>` - Reproducible build ID (12-char hash)

**Format:** KubeVirt containerDisk

**Layers:**

1. `/disk/disk.qcow2` - VM image
2. `/disk/.konductor` - Provenance with OCI digest
3. `/disk/build.log` - Serial console output

### Provenance File

**Path:** `.konductor` (build host), `/.konductor` (inside VM)

**Format:** TOML

**Fields:**

```toml
[konductor]
git_commit = "<40-char SHA>"
git_branch = "main"
git_remote = "https://github.com/containercraft/konductor.git"
git_dirty = 0
nix_version = "2.24.0"
nix_hash = "sha256-..."
nix_drv = "<12-char hash>"
flake_lock_sha256 = "<64-char SHA>"
build_date = "2025-02-20T10:30:00-08:00"
build_host = "konductor-builder"
build_user = "runner"
qemu = "8.2.0"
build_hw_vendor = "Dell Inc."
build_hw_product = "PowerEdge R730"
build_hw_serial = "ABC123"
strict = false
oci_image = "registry.docker.arpa/containercraft/konductor"
oci_tags = ["latest-qcow2", "qcow2-abc123", "qcow2-def456"]
image_sha256 = "def456..."
image_size = "3.8G"
oci_digest = "sha256:abc123..."
```

---

## Supply Chain Provenance

### Attestation Flow

Every artifact carries verifiable provenance through the supply chain:

```text
SOURCE ──► NIX ──► BUILD ──► SEAL ──► OCI ──► PUSH
  │        │        │         │        │       │
  ▼        ▼        ▼         ▼        ▼       ▼
┌──────────────────────────────────────────────────┐
│ /.konductor (progressive attestation)            │
├──────────────────────────────────────────────────┤
│ Source:     git_commit, git_branch, git_remote   │
│ Reproducible: nix_drv, nix_hash, flake_lock      │
│ Build:      build_date, build_host, build_hw_*   │
│ Seal:       image_sha256, image_size             │
│ OCI:        oci_image, oci_tags                  │
│ Registry:   oci_digest                           │
└──────────────────────────────────────────────────┘
```

### Trust Gates

**Reproducibility gate:** `git_dirty = 0`

- Only clean git trees get deterministic tags (`qcow2-<commit>`)
- Dirty trees get `qcow2-dirty` tag
- Prevents accidental promotion of unreproducible builds

**Validation gate:** `build:qcow2:validate` + `build:qcow2:runner-test`

- SSH access must succeed
- Runner workflow must complete successfully
- Prevents promotion of broken images

**Promotion gate:** Manual (`build:qcow2:promote`)

- Requires explicit credentials (DOCKER_TOKEN or GITHUB_TOKEN)
- Requires validation to have passed
- Prevents accidental public releases

### Verification

**From running VM:**

```bash {"name":"verify:self-pull","excludeFromRunAll":"true","tag":"type:example"}
# Parse provenance
oci_image=$(sed -n 's/^oci_image = "\(.*\)"$/\1/p' /.konductor)
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)

# Pull source container
docker pull "${oci_image}:qcow2-${git_commit}"
```

**Verify image matches build:**

```bash {"name":"verify:digest","excludeFromRunAll":"true","tag":"type:example"}
# Compare digest from provenance with actual image
expected=$(grep '^oci_digest = ' .konductor | cut -d'"' -f2)
actual=$(skopeo inspect docker://registry.docker.arpa/containercraft/konductor:latest-qcow2 | jq -r '.Digest')
[ "$expected" = "$actual" ] && echo "✓ Digest match" || echo "✗ Digest mismatch"
```

---

## Troubleshooting

### Build Failures

**Problem:** Nix build fails with "disk full"

**Solution:**

```bash {"name":"troubleshoot:disk-space","excludeFromRunAll":"true","tag":"type:example"}
# Clean nix store
nix-collect-garbage -d

# Check disk space
df -h .
```

---

**Problem:** VM fails to boot (timeout waiting for SSH)

**Solution:**

```bash {"name":"troubleshoot:vm-boot","excludeFromRunAll":"true","tag":"type:example"}
# Check VM log for errors
tail -100 build-vm.log

# Look for cloud-init errors
grep -i error build-vm.log
grep -i fail build-vm.log
```

---

**Problem:** Permission denied on `/dev/kvm`

**Solution:**

```bash {"name":"troubleshoot:kvm","excludeFromRunAll":"true","tag":"type:example"}
# Add user to kvm group
sudo usermod -aG kvm $USER

# Re-login or run
newgrp kvm
```

---

### Registry Issues

**Problem:** `docker push` fails with TLS error

**Solution:**

```bash {"name":"troubleshoot:registry-tls","excludeFromRunAll":"true","tag":"type:example"}
# Reinstall cluster CA
runme run registry:trust

# Verify CA is installed
ls -l /etc/docker/certs.d/registry.docker.arpa/ca.crt
```

---

**Problem:** `skopeo copy` fails with authentication error

**Solution:**

```bash {"name":"troubleshoot:registry-auth","excludeFromRunAll":"true","tag":"type:example"}
# Re-authenticate
runme run registry:login

# Verify credentials
jq '.auths["registry.docker.arpa"]' ${WORKSPACE_ROOT}/.docker/config.json
```

---

### Cluster Issues

**Problem:** `cluster:up` fails with "port already in use"

**Solution:**

```bash {"name":"troubleshoot:cluster-ports","excludeFromRunAll":"true","tag":"type:example"}
# Clean existing cluster
runme run cluster:down

# Check for stale containers
docker ps -a | grep talos

# Force clean
docker rm -f $(docker ps -a -q --filter "name=talos")
```

---

**Problem:** VM fails to deploy to KubeVirt

**Solution:**

```bash {"name":"troubleshoot:kubevirt","excludeFromRunAll":"true","tag":"type:example"}
# Check VMI status
kubectl get vmi -n konductor

# Check VMI events
kubectl describe vmi konductor -n konductor

# Check image pull
kubectl get events -n konductor | grep Pull
```

---

### Validation Issues

**Problem:** `build:qcow2:runner-test` fails with workflow timeout

**Solution:**

```bash {"name":"troubleshoot:runner","excludeFromRunAll":"true","tag":"type:example"}
# Check runner pod logs
kubectl logs -n forgejo -l app=forgejo-runner

# Check workflow in Forgejo UI
echo "https://git.docker.arpa/braincraft/k9/actions"

# Manually trigger workflow
kubectl exec -n forgejo deployment/forgejo-deployment -c forgejo -- \
  wget -qO- --post-data='{"ref":"main"}' \
    --header="Authorization: token <token>" \
    "http://localhost:3000/api/v1/repos/braincraft/k9/actions/workflows/validate-environment.yaml/dispatches"
```

---

### Environment Variables

Override default values for customization:

```bash {"name":"example:env-vars","excludeFromRunAll":"true","tag":"type:example"}
# Build configuration
export SKIP_NIX_BUILD=false      # Skip nix build (reuse existing)
export SKIP_VM_PHASE=false       # Skip VM configuration (reuse existing image)
export SKIP_COMPRESS=false       # Skip ZSTD compression (faster, larger image)

# Registry configuration
export CONTAINER_REGISTRY="registry.docker.arpa"
export CONTAINER_IMAGE="containercraft/konductor"
export CONTAINER_TAG="latest-qcow2"

# VM port forwarding
export QCOW2_SSH_PORT=2222       # SSH port on host
export QCOW2_VSCODE_PORT=18080   # VS Code port on host
export QCOW2_TTYD_PORT=17681     # TTYD port on host

# Promotion
export PROMOTE_REGISTRY="docker.io"
export PROMOTE_IMAGE="containercraft/konductor"
export DOCKER_TOKEN="<your-token>"
```

---

## Additional Resources

- **OCI.md**: Standalone offline build documentation (core build mechanics)
- **CLOUD_INIT_NIXOS_INTEGRATION.md**: Cloud-init integration patterns
- **VERIFY.md**: Image verification procedures
- **UPDATE.md**: Update procedures for flake inputs

---

## Quick Reference Cards

### Daily Development

```bash {"name":"cheatsheet:dev","excludeFromRunAll":"true","tag":"type:example"}
# Fast iteration
runme run build:qcow2:publish   # Build + push
runme run build:qcow2:start     # Boot VM
runme run build:qcow2:ssh       # SSH into VM
runme run build:qcow2:stop      # Shutdown VM
```

### Release Workflow

```bash {"name":"cheatsheet:release","excludeFromRunAll":"true","tag":"type:example"}
# Full pipeline
runme run build:qcow2:all       # Build + validate
export DOCKER_TOKEN="<token>"
runme run build:qcow2:promote   # Promote to docker.io
```

### Debugging

```bash {"name":"cheatsheet:debug","excludeFromRunAll":"true","tag":"type:example"}
# Check build logs
tail -100 build-vm.log

# Check cluster
kubectl get nodes
kubectl get po -A

# Check registry
runme run registry:tags

# Check VM in cluster
kubectl get vmi -n konductor
kubectl describe vmi konductor -n konductor
```
