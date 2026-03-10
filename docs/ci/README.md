---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: scope:ci,target:qcow2
runme:
  version: v3
---

# Konductor CI Pipeline

Complete build, validation, and promotion pipeline for airgap-ready NixOS VM images with supply chain attestation.

## Contents

- [Overview](#overview)
- [Pipeline Architecture](#pipeline-architecture)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Workflows](#workflows)
  - [Full Pipeline](#full-pipeline)
  - [Development Build](#development-build)
  - [Validation Only](#validation-only)
  - [Promotion](#promotion)
- [Pipeline Orchestrator](#pipeline-orchestrator)
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
- **Parallel**: Build and cluster deploy run concurrently (saves 5-10 min)

---

## Pipeline Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  ci:pipeline — Complete Pipeline with Parallel Build + Platform             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PREFLIGHT (inline, <1s)                                                    │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ LD_LIBRARY_PATH, Docker daemon, OVMF firmware              │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                 │
│  ┌─────────────────────────────┬──────────────────────────────┐            │
│  │ PARALLEL                    │ PARALLEL                      │            │
│  │                             │                                │            │
│  │ BUILD PHASE (build.md)      │ PLATFORM PHASE (platform.md)  │            │
│  │ ┌────────────────────────┐  │ ┌─────────────────────────┐   │            │
│  │ │ build:all               │  │ │ platform:up              │   │            │
│  │ │  _build:clean           │  │ │  mise compose:clean      │   │            │
│  │ │  _build:preflight       │  │ │  mise compose:up         │   │            │
│  │ │  _build:nix             │  │ │  mise pulumi:up          │   │            │
│  │ │  _build:cloudinit       │  │ └─────────────────────────┘   │            │
│  │ │  _build:img:reset       │  │        5-10 min               │            │
│  │ │  _build:vm:boot         │  │                                │            │
│  │ │  _build:vm:wait         │  │                                │            │
│  │ │  _build:vm:sync         │  │                                │            │
│  │ │  _build:vm:rebuild      │  │                                │            │
│  │ │  _build:vm:pki:test     │  │                                │            │
│  │ │  _build:vm:pki:status   │  │                                │            │
│  │ │  _build:vm:provenance   │  │                                │            │
│  │ │  _build:vm:gc           │  │                                │            │
│  │ │  _build:vm:zero         │  │                                │            │
│  │ │  _build:vm:halt         │  │                                │            │
│  │ │  _build:img:clean       │  │                                │            │
│  │ │  _build:img:compress    │  │                                │            │
│  │ │  _build:img:sparsify    │  │                                │            │
│  │ │  _build:tmp:clean       │  │                                │            │
│  │ │  _build:verify          │  │                                │            │
│  │ │  _build:container       │  │                                │            │
│  │ └────────────────────────┘  │                                │            │
│  │        30-60 min            │                                │            │
│  └─────────────────────────────┴──────────────────────────────┘            │
│                           ↓ BARRIER (wait for both)                        │
│  REGISTRY PHASE (registry.md)                                               │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ registry:trust   Install cluster CA for Docker + Skopeo    │             │
│  │ registry:login   Authenticate to registry.docker.arpa      │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                 │
│  PUSH PHASE (push.md)                                                       │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ push:image   Multi-tag skopeo copy to local registry       │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                 │
│  VERIFICATION (registry.md)                                                 │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ registry:tags   Confirm pushed tags landed                  │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                 │
│  VALIDATION PHASE (validate.md)                                             │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ validate:deploy     Deploy VM to KubeVirt + SSH test        │             │
│  │ validate:services   Port-forward + curl web terminals       │             │
│  │ validate:runner     Forgejo push + dispatch + poll          │             │
│  └────────────────────────────────────────────────────────────┘             │
│                           ↓                                                 │
│  ═══════════════════════════════════════════════════════════════            │
│   PIPELINE COMPLETE — manual promotion gate below                           │
│  ═══════════════════════════════════════════════════════════════            │
│                           ↓                                                 │
│  PROMOTION PHASE (promote.md) — manual, not in ci:pipeline                 │
│  ┌────────────────────────────────────────────────────────────┐             │
│  │ promote:image   Copy to docker.io / ghcr.io with all tags  │             │
│  └────────────────────────────────────────────────────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**File responsibilities:**

| File | Role | Tasks |
|------|------|-------|
| `README.md` | Sole orchestrator + pipeline docs | `ci:pipeline` |
| `build.md` | Source → sealed QCOW2 → OCI containerDisk | `--tag=pipeline:all`, `--tag=pipeline:image`, 22 `_build:*` phases |
| `platform.md` | Cluster lifecycle (Talos + Pulumi) | `platform:up`, `platform:down`, `platform:status` |
| `registry.md` | Registry trust, auth, inspection | `registry:trust`, `registry:login`, `registry:list`, `registry:tags` |
| `push.md` | Push to local registry | `push:image` |
| `validate.md` | KubeVirt deploy + service checks + runner test | `validate:deploy`, `validate:services`, `validate:runner` |
| `promote.md` | Manual gate → public registry copy | `promote:image` |
| `verify.md` | Build verification (runs inside VM) | `verify:help`, `verify:provenance`, `verify:source`, `verify:flake`, `verify:nix`, `verify:all`, `verify:reproduce` |
| `dev.md` | Developer workflow tools | `dev:clean`, `dev:start`, `dev:ssh`, `dev:stop`, `dev:rebase`, `dev:vendor`, `dev:vendor:online`, `dev:log`, `dev:kill` |

No file ever calls another file. Only `ci:pipeline` orchestrates cross-file execution.
Exception: `dev.md` calls `build.md` internal tasks for VM lifecycle (dev-only, never CI).

---

## Quick Start

### One-Command Full Pipeline

```bash {"name":"quickstart:pipeline","excludeFromRunAll":"true","tag":"type:example"}
# Complete end-to-end: build → cluster → validate (parallel build+platform)
runme run --filename docs/ci/README.md ci:pipeline
```

### Development Iteration

```bash {"name":"quickstart:dev","excludeFromRunAll":"true","tag":"type:example"}
# Build image + containerDisk
runme run --all --tag=pipeline:all --filename docs/ci/build.md

# Interactive development: boot VM for testing
runme run --filename docs/ci/dev.md dev:start
runme run --filename docs/ci/dev.md dev:ssh
runme run --filename docs/ci/dev.md dev:stop
```

### Validation Only

```bash {"name":"quickstart:validate","excludeFromRunAll":"true","tag":"type:example"}
# Validate existing image in cluster
runme run --filename docs/ci/validate.md validate:deploy
runme run --filename docs/ci/validate.md validate:services
runme run --filename docs/ci/validate.md validate:runner
```

### Promotion

```bash {"name":"quickstart:promote","excludeFromRunAll":"true","tag":"type:example"}
# Copy validated image to public registry
export DOCKER_TOKEN="<your-token>"
runme run --filename docs/ci/promote.md promote:image
```

---

## Task Reference

### Build Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `build:all` | build.md | Full pipeline: clean → nix → VM → seal → container | 30-60 min |
| `build:image` | build.md | Build QCOW2 only (no container packaging) | 30-60 min |

### Platform Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `platform:up` | platform.md | Start Talos + deploy platform | 5-10 min |
| `platform:down` | platform.md | Destroy cluster | 1-2 min |
| `platform:status` | platform.md | Check cluster health | <1 min |

### Registry Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `registry:trust` | registry.md | Install cluster CA | <1 min |
| `registry:login` | registry.md | Authenticate to registry | <1 min |
| `registry:list` | registry.md | List images in registry | <1 min |
| `registry:tags` | registry.md | List tags for konductor image | <1 min |

### Push Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `push:image` | push.md | Multi-tag push to local registry | 1-2 min |

### Validation Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `validate:deploy` | validate.md | Deploy to KubeVirt + SSH test | 3-5 min |
| `validate:services` | validate.md | Test web terminals (non-blocking) | 1-2 min |
| `validate:runner` | validate.md | Forgejo runner workflow test | 5-10 min |

### Promotion Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `promote:image` | promote.md | Copy to public registry | 2-5 min |

### Development Tasks

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `dev:clean` | dev.md | Reset build state | <1 min |
| `dev:start` | dev.md | Boot VM for development | 2-3 min |
| `dev:ssh` | dev.md | SSH into running VM | instant |
| `dev:stop` | dev.md | Shutdown VM | <1 min |
| `dev:rebase` | dev.md | Rebuild NixOS host from flake | 5-10 min |
| `dev:vendor` | dev.md | Vendor flake inputs offline | 2-5 min |
| `dev:vendor:online` | dev.md | Online refresh + vendor | 2-5 min |
| `dev:log` | dev.md | View serial console log | instant |
| `dev:kill` | dev.md | Force kill QEMU process | instant |

### Verification Tasks (runs inside built VM)

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `verify:help` | verify.md | Usage text | instant |
| `verify:provenance` | verify.md | Display /.konductor | instant |
| `verify:source` | verify.md | Verify git commit | instant |
| `verify:flake` | verify.md | Verify flake.lock sha256 | instant |
| `verify:nix` | verify.md | Verify nix derivation | <1 min |
| `verify:all` | verify.md | All verification checks | <1 min |
| `verify:reproduce` | verify.md | Full reproduction build | 30-60 min |

### Complete Pipeline

| Task | File | Description | Duration |
|------|------|-------------|----------|
| `ci:pipeline` | README.md | Full end-to-end with parallel build+platform | 45-75 min |

---

## Workflows

### Full Pipeline

Complete end-to-end with cluster validation and parallel execution.

```text
┌────────────────────────────────────────┐
│ Full Pipeline Workflow                 │
├────────────────────────────────────────┤
│ ┌─ build:all (30-60 min) ────────┐    │
│ │                                 ├──► │
│ └─ platform:up (5-10 min) ───────┘    │
│    registry:trust + registry:login     │
│    push:image                          │
│    validate:deploy                     │
│    validate:services                   │
│    validate:runner                     │
│    ─── manual gate ───                 │
│    promote:image                       │
└────────────────────────────────────────┘
```

**Use case:** Release builds, CI/CD pipelines.

```bash {"name":"workflow:full","excludeFromRunAll":"true","tag":"type:example"}
# One command runs entire pipeline (parallel build+platform)
runme run --filename docs/ci/README.md ci:pipeline
```

---

### Development Build

Fast iteration cycle for development.

```text
┌────────────────────────────────────────┐
│ Development Workflow                   │
├────────────────────────────────────────┤
│ 1. build:all                           │
│    └─ Build + package                  │
│                                        │
│ 2. (optional) dev:start                │
│    └─ Boot VM for interactive testing  │
└────────────────────────────────────────┘
```

**Use case:** Iterating on flake changes, testing builds locally.

```bash {"name":"workflow:dev","excludeFromRunAll":"true","tag":"type:example"}
# Build and package
runme run --all --tag=pipeline:all --filename docs/ci/build.md

# Optional: boot VM for testing
runme run --filename docs/ci/dev.md dev:start
ssh -p 2222 kc2admin@localhost
runme run --filename docs/ci/dev.md dev:stop
```

---

### Validation Only

Validate existing image without rebuilding.

```text
┌────────────────────────────────────────┐
│ Validation Workflow                    │
├────────────────────────────────────────┤
│ Prerequisites: cluster running, image  │
│                already pushed          │
│                                        │
│ 1. validate:deploy                     │
│ 2. validate:services                   │
│ 3. validate:runner                     │
└────────────────────────────────────────┘
```

**Use case:** Testing existing image, debugging cluster issues.

```bash {"name":"workflow:validate","excludeFromRunAll":"true","tag":"type:example"}
# Validate existing image
runme run --filename docs/ci/validate.md validate:deploy
runme run --filename docs/ci/validate.md validate:services
runme run --filename docs/ci/validate.md validate:runner
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
│ 1. Set credentials (DOCKER_TOKEN)      │
│ 2. promote:image                       │
└────────────────────────────────────────┘
```

**Use case:** Publishing releases to docker.io or ghcr.io.

```bash {"name":"workflow:promote","excludeFromRunAll":"true","tag":"type:example"}
# Set credentials
export DOCKER_TOKEN="<your-docker-hub-token>"

# Promote to docker.io
runme run --filename docs/ci/promote.md promote:image

# Or promote to ghcr.io
export GITHUB_TOKEN="<your-github-token>"
export PROMOTE_REGISTRY="ghcr.io"
export PROMOTE_IMAGE="your-org/konductor"
runme run --filename docs/ci/promote.md promote:image
```

---

## Pipeline Orchestrator

### ci:pipeline

Complete end-to-end pipeline with parallel build and platform deployment.

**Pipeline stages:**

1. **Preflight**: Fail-fast environment checks (LD_LIBRARY_PATH, Docker, OVMF)
2. **Build** (parallel): `build:all` — Full QCOW2 + containerDisk build
3. **Platform** (parallel): `platform:up` — Start Talos + deploy platform
4. **Registry**: `registry:trust` + `registry:login` — Install CA + authenticate
5. **Push**: `push:image` — Multi-tag push to local registry
6. **Verify push**: `registry:tags` — Confirm tags landed
7. **Validate**: `validate:deploy` — Deploy to KubeVirt + SSH test
8. **Services**: `validate:services` — Web terminal health checks
9. **Runner**: `validate:runner` — Forgejo workflow validation

**Note:** Promotion (`promote:image`) is NOT included. It is a manual gate after validation passes.

**Duration:** 45-75 minutes (parallel build+platform saves 5-10 min vs sequential)

**Prerequisites:** Docker running, sufficient resources (8GB RAM, 100GB disk)

```sh {"name":"ci:pipeline","excludeFromRunAll":"true","tag":"type:entry,duration:very-slow"}
set -e
CI_DIR="docs/ci"

# ─────────────────────────────────────────────────────────────────────
# PREFLIGHT — fail-fast for env gaps that waste 60+ minute build cycles
# ─────────────────────────────────────────────────────────────────────
ERRORS=0

# LD_LIBRARY_PATH — pulumi/grpcio ImportError: libstdc++.so.6 at platform:up
if [ -n "$LD_LIBRARY_PATH" ] && find ${LD_LIBRARY_PATH//:/ } -name 'libstdc++.so*' 2>/dev/null | grep -q .; then
    echo "✓ libstdc++.so reachable"
else
    echo "✗ libstdc++.so not found in LD_LIBRARY_PATH (pulumi/grpcio will fail at platform:up)"
    ((ERRORS++))
fi

# Docker daemon — required for container build, push, and cluster phases
docker info &>/dev/null && echo "✓ Docker daemon reachable" || { echo "✗ Docker daemon not reachable"; ((ERRORS++)); }

# OVMF firmware — QEMU VM won't boot without EFI firmware
[ -n "$OVMF_CODE" ] && [ -f "$OVMF_CODE" ] && echo "✓ OVMF firmware present" || { echo "✗ OVMF_CODE not set or missing"; ((ERRORS++)); }

[ "$ERRORS" -eq 0 ] || { echo "✗ $ERRORS preflight error(s)"; exit 1; }

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ci:pipeline — Complete End-to-End Pipeline (Parallel Build + Platform)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Pipeline stages:"
echo "    1+2. Build + package ║ Start cluster + deploy platform  (PARALLEL)"
echo "    3.   Install cluster CA + authenticate"
echo "    4.   Push to registry"
echo "    5.   Verify pushed tags"
echo "    6.   Deploy to KubeVirt + validate"
echo "    7.   Test web terminal services"
echo "    8.   Test Forgejo runner workflow"
echo ""
echo "  Duration: 45-75 minutes (parallel build+platform)"
echo "  Prerequisites: Docker, 8GB RAM, 100GB disk"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────
# PHASE 1+2: Build image + Deploy platform IN PARALLEL
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 1+2: Build + package ║ Start cluster + deploy platform (PARALLEL)..."

runme run --all --tag=pipeline:all --filename "$CI_DIR/build.md" &
BUILD_PID=$!

runme run --direnv=true --load-env=false --filename "$CI_DIR/platform.md" platform:up &
PLATFORM_PID=$!

# Wait for both — fail-fast on either
BUILD_OK=0
PLATFORM_OK=0

wait $BUILD_PID || BUILD_OK=1
wait $PLATFORM_PID || PLATFORM_OK=1

if [ "$BUILD_OK" -ne 0 ]; then
    echo "✗ Image build failed"
    # If platform is still running, let it finish (don't orphan)
    exit 1
fi
if [ "$PLATFORM_OK" -ne 0 ]; then
    echo "✗ Platform deploy failed"
    exit 1
fi

echo "✓ Build + platform complete"

# ─────────────────────────────────────────────────────────────────────
# PHASE 3: Registry trust + login
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 3: Install cluster CA + authenticate..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:trust
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:login

# ─────────────────────────────────────────────────────────────────────
# PHASE 4: Push to registry
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 4: Push to registry..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/push.md" push:image

# ─────────────────────────────────────────────────────────────────────
# PHASE 5: Verify pushed tags
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 5: Verify pushed tags..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:tags

# ─────────────────────────────────────────────────────────────────────
# PHASE 6: Deploy to KubeVirt + validate
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 6: Deploy to KubeVirt + validate..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:deploy

# ─────────────────────────────────────────────────────────────────────
# PHASE 7: Test web terminal services
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 7: Test web terminal services..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:services

# ─────────────────────────────────────────────────────────────────────
# PHASE 8: Test Forgejo runner workflow
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Phase 8: Test Forgejo runner workflow..."
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:runner

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✅ Pipeline complete! Image validated and ready for promotion."
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Review validation results above"
echo "  2. Set credentials: export DOCKER_TOKEN=<your-token>"
echo "  3. Promote: runme run --filename docs/ci/promote.md promote:image"
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

**Validation gate:** `validate:deploy` + `validate:runner`

- SSH access must succeed
- Runner workflow must complete successfully
- Prevents promotion of broken images

**Promotion gate:** Manual (`promote:image`)

- Requires explicit credentials (DOCKER_TOKEN or GITHUB_TOKEN)
- Requires validation to have passed
- Prevents accidental public releases

### Verification

**From running VM:**

```bash {"name":"example:verify-self-pull","excludeFromRunAll":"true","tag":"type:example"}
# Parse provenance
oci_image=$(sed -n 's/^oci_image = "\(.*\)"$/\1/p' /.konductor)
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)

# Pull source container
docker pull "${oci_image}:qcow2-${git_commit}"
```

**Verify image matches build:**

```bash {"name":"example:verify-digest","excludeFromRunAll":"true","tag":"type:example"}
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
runme run --filename docs/ci/registry.md registry:trust

# Verify CA is installed
ls -l /etc/docker/certs.d/registry.docker.arpa/ca.crt
```

---

**Problem:** `skopeo copy` fails with authentication error

**Solution:**

```bash {"name":"troubleshoot:registry-auth","excludeFromRunAll":"true","tag":"type:example"}
# Re-authenticate
runme run --filename docs/ci/registry.md registry:login

# Verify credentials
jq '.auths["registry.docker.arpa"]' ${WORKSPACE_ROOT}/.docker/config.json
```

---

### Cluster Issues

**Problem:** `platform:up` fails with "port already in use"

**Solution:**

```bash {"name":"troubleshoot:cluster-ports","excludeFromRunAll":"true","tag":"type:example"}
# Clean existing cluster
runme run --filename docs/ci/platform.md platform:down

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
