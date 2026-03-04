# CI Pipeline Overhaul: Design, Architecture & Implementation

> **Scope:** Complete rewrite of `docs/developer_guide/qcow2/{BUILD,OCI,VERIFY}.md` into `docs/ci/`.
> **Outcome:** `rm -rf docs/developer_guide/qcow2/` with zero functional regression.
> **Constraint:** Every bash code block must preserve exact working syntax from prior art. No placeholders. No stubs. No "TODO later."

---

## Smoke Test Runbook

Run each command sequentially. Record result (PASS/FAIL/SKIP + notes) after each.
Do NOT fix anything during the run. Collect all findings, then fix together after.

### Phase A: Individual task smoke tests (granular, one at a time)

Each test validates that runme can parse, resolve, and (where safe) execute the task.
Tests marked `[DRY]` are structure-only (runme list) — the task would be destructive or
requires infrastructure not present. Tests marked `[RUN]` are safe to execute.

#### A1: build.md — Build pipeline tasks

```
# Verify all build tasks are listed
runme list --filename docs/ci/build.md
```
- [ ] **A1.1** `runme list --filename docs/ci/build.md` — all 23 tasks listed
  - Result:

```
# DRY — clean would nuke build artifacts, just verify it parses
runme print --filename docs/ci/build.md _build:clean
```
- [ ] **A1.2** `runme print --filename docs/ci/build.md _build:clean` — prints bash body
  - Result:

```
# DRY — preflight is safe but long, verify parse
runme print --filename docs/ci/build.md _build:preflight
```
- [ ] **A1.3** `runme print --filename docs/ci/build.md _build:preflight` — prints bash body
  - Result:

```
# DRY — nix build is slow, verify parse
runme print --filename docs/ci/build.md _build:nix
```
- [ ] **A1.4** `runme print --filename docs/ci/build.md _build:nix` — prints bash body
  - Result:

```
# DRY — cloudinit needs OVMF vars
runme print --filename docs/ci/build.md _build:cloudinit
```
- [ ] **A1.5** `runme print --filename docs/ci/build.md _build:cloudinit` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:img:reset
```
- [ ] **A1.6** `runme print --filename docs/ci/build.md _build:img:reset` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:boot
```
- [ ] **A1.7** `runme print --filename docs/ci/build.md _build:vm:boot` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:wait
```
- [ ] **A1.8** `runme print --filename docs/ci/build.md _build:vm:wait` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:sync
```
- [ ] **A1.9** `runme print --filename docs/ci/build.md _build:vm:sync` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:rebuild
```
- [ ] **A1.10** `runme print --filename docs/ci/build.md _build:vm:rebuild` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:pki:test
```
- [ ] **A1.11** `runme print --filename docs/ci/build.md _build:vm:pki:test` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:pki:status
```
- [ ] **A1.12** `runme print --filename docs/ci/build.md _build:vm:pki:status` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:provenance
```
- [ ] **A1.13** `runme print --filename docs/ci/build.md _build:vm:provenance` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:gc
```
- [ ] **A1.14** `runme print --filename docs/ci/build.md _build:vm:gc` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:zero
```
- [ ] **A1.15** `runme print --filename docs/ci/build.md _build:vm:zero` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:vm:halt
```
- [ ] **A1.16** `runme print --filename docs/ci/build.md _build:vm:halt` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:img:clean
```
- [ ] **A1.17** `runme print --filename docs/ci/build.md _build:img:clean` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:img:compress
```
- [ ] **A1.18** `runme print --filename docs/ci/build.md _build:img:compress` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:img:sparsify
```
- [ ] **A1.19** `runme print --filename docs/ci/build.md _build:img:sparsify` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:tmp:clean
```
- [ ] **A1.20** `runme print --filename docs/ci/build.md _build:tmp:clean` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:verify
```
- [ ] **A1.21** `runme print --filename docs/ci/build.md _build:verify` — prints bash body
  - Result:

```
runme print --filename docs/ci/build.md _build:container
```
- [ ] **A1.22** `runme print --filename docs/ci/build.md _build:container` — prints bash body
  - Result:

```
# Verify entry points parse (don't run — they orchestrate the full build)
runme print --filename docs/ci/build.md build:all
```
- [ ] **A1.23** `runme print --filename docs/ci/build.md build:all` — prints orchestrator loop
  - Result:

```
runme print --filename docs/ci/build.md build:image
```
- [ ] **A1.24** `runme print --filename docs/ci/build.md build:image` — prints orchestrator loop
  - Result:

#### A2: platform.md — Cluster lifecycle

```
runme list --filename docs/ci/platform.md
```
- [ ] **A2.1** `runme list --filename docs/ci/platform.md` — 3 tasks listed
  - Result:

```
runme print --filename docs/ci/platform.md platform:up
```
- [ ] **A2.2** `runme print --filename docs/ci/platform.md platform:up` — prints bash body
  - Result:

```
runme print --filename docs/ci/platform.md platform:down
```
- [ ] **A2.3** `runme print --filename docs/ci/platform.md platform:down` — prints bash body
  - Result:

```
runme print --filename docs/ci/platform.md platform:status
```
- [ ] **A2.4** `runme print --filename docs/ci/platform.md platform:status` — prints bash body
  - Result:

#### A3: registry.md — Registry operations

```
runme list --filename docs/ci/registry.md
```
- [ ] **A3.1** `runme list --filename docs/ci/registry.md` — 4 tasks listed
  - Result:

```
runme print --filename docs/ci/registry.md registry:trust
```
- [ ] **A3.2** `runme print --filename docs/ci/registry.md registry:trust` — prints bash body
  - Result:

```
runme print --filename docs/ci/registry.md registry:login
```
- [ ] **A3.3** `runme print --filename docs/ci/registry.md registry:login` — prints bash body
  - Result:

```
# RUN — safe, readonly, will fail without cluster (expected)
runme run --filename docs/ci/registry.md registry:list
```
- [ ] **A3.4** `runme run --filename docs/ci/registry.md registry:list` — runs (expect connection refused without cluster)
  - Result:

```
runme run --filename docs/ci/registry.md registry:tags
```
- [ ] **A3.5** `runme run --filename docs/ci/registry.md registry:tags` — runs (expect connection refused without cluster)
  - Result:

#### A4: push.md — Push to registry

```
runme list --filename docs/ci/push.md
```
- [ ] **A4.1** `runme list --filename docs/ci/push.md` — 1 task listed
  - Result:

```
runme print --filename docs/ci/push.md push:image
```
- [ ] **A4.2** `runme print --filename docs/ci/push.md push:image` — prints bash body
  - Result:

#### A5: validate.md — Validation tasks

```
runme list --filename docs/ci/validate.md
```
- [ ] **A5.1** `runme list --filename docs/ci/validate.md` — 3 tasks listed
  - Result:

```
runme print --filename docs/ci/validate.md validate:deploy
```
- [ ] **A5.2** `runme print --filename docs/ci/validate.md validate:deploy` — prints bash body
  - Result:

```
runme print --filename docs/ci/validate.md validate:services
```
- [ ] **A5.3** `runme print --filename docs/ci/validate.md validate:services` — prints bash body
  - Result:

```
runme print --filename docs/ci/validate.md validate:runner
```
- [ ] **A5.4** `runme print --filename docs/ci/validate.md validate:runner` — prints bash body
  - Result:

#### A6: promote.md — Promotion

```
runme list --filename docs/ci/promote.md
```
- [ ] **A6.1** `runme list --filename docs/ci/promote.md` — 1 task listed
  - Result:

```
runme print --filename docs/ci/promote.md promote:image
```
- [ ] **A6.2** `runme print --filename docs/ci/promote.md promote:image` — prints bash body
  - Result:

#### A7: verify.md — Build verification

```
runme list --filename docs/ci/verify.md
```
- [ ] **A7.1** `runme list --filename docs/ci/verify.md` — 7 tasks listed
  - Result:

```
# RUN — safe, just prints help text
runme run --filename docs/ci/verify.md verify:help
```
- [ ] **A7.2** `runme run --filename docs/ci/verify.md verify:help` — prints usage text
  - Result:

```
runme print --filename docs/ci/verify.md verify:provenance
```
- [ ] **A7.3** `runme print --filename docs/ci/verify.md verify:provenance` — prints bash body
  - Result:

```
runme print --filename docs/ci/verify.md verify:source
```
- [ ] **A7.4** `runme print --filename docs/ci/verify.md verify:source` — prints bash body
  - Result:

```
runme print --filename docs/ci/verify.md verify:flake
```
- [ ] **A7.5** `runme print --filename docs/ci/verify.md verify:flake` — prints bash body
  - Result:

```
runme print --filename docs/ci/verify.md verify:nix
```
- [ ] **A7.6** `runme print --filename docs/ci/verify.md verify:nix` — prints bash body
  - Result:

```
runme print --filename docs/ci/verify.md verify:all
```
- [ ] **A7.7** `runme print --filename docs/ci/verify.md verify:all` — prints bash body
  - Result:

```
runme print --filename docs/ci/verify.md verify:reproduce
```
- [ ] **A7.8** `runme print --filename docs/ci/verify.md verify:reproduce` — prints bash body
  - Result:

#### A8: dev.md — Developer tools

```
runme list --filename docs/ci/dev.md
```
- [ ] **A8.1** `runme list --filename docs/ci/dev.md` — 9 tasks listed
  - Result:

```
runme print --filename docs/ci/dev.md dev:clean
```
- [ ] **A8.2** `runme print --filename docs/ci/dev.md dev:clean` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:start
```
- [ ] **A8.3** `runme print --filename docs/ci/dev.md dev:start` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:ssh
```
- [ ] **A8.4** `runme print --filename docs/ci/dev.md dev:ssh` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:stop
```
- [ ] **A8.5** `runme print --filename docs/ci/dev.md dev:stop` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:rebase
```
- [ ] **A8.6** `runme print --filename docs/ci/dev.md dev:rebase` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:vendor
```
- [ ] **A8.7** `runme print --filename docs/ci/dev.md dev:vendor` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:vendor:online
```
- [ ] **A8.8** `runme print --filename docs/ci/dev.md dev:vendor:online` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:log
```
- [ ] **A8.9** `runme print --filename docs/ci/dev.md dev:log` — prints bash body
  - Result:

```
runme print --filename docs/ci/dev.md dev:kill
```
- [ ] **A8.10** `runme print --filename docs/ci/dev.md dev:kill` — prints bash body
  - Result:

#### A9: README.md — Orchestrator

```
runme list --filename docs/ci/README.md
```
- [ ] **A9.1** `runme list --filename docs/ci/README.md` — `ci:pipeline` + example/workflow/troubleshoot tasks listed
  - Result:

```
runme print --filename docs/ci/README.md ci:pipeline
```
- [ ] **A9.2** `runme print --filename docs/ci/README.md ci:pipeline` — prints full orchestrator with parallel logic
  - Result:

### Phase B: Safe execution tests (tasks that can actually run)

These tasks are safe to execute — they either produce only stdout or fail gracefully
when infrastructure is absent.

```
# Preflight — the big environment validator
runme run --filename docs/ci/build.md _build:preflight
```
- [ ] **B1** `runme run --filename docs/ci/build.md _build:preflight` — runs full env validation
  - Result:

```
# Registry list — will fail with connection refused (no cluster), but proves runme execution works
runme run --filename docs/ci/registry.md registry:list
```
- [ ] **B2** `runme run --filename docs/ci/registry.md registry:list` — runs, expect connection refused
  - Result:

```
# Registry tags — same
runme run --filename docs/ci/registry.md registry:tags
```
- [ ] **B3** `runme run --filename docs/ci/registry.md registry:tags` — runs, expect connection refused
  - Result:

```
# Platform status — will fail without cluster, but proves execution
runme run --filename docs/ci/platform.md platform:status
```
- [ ] **B4** `runme run --filename docs/ci/platform.md platform:status` — runs, expect kubectl error
  - Result:

```
# Verify help — pure stdout
runme run --filename docs/ci/verify.md verify:help
```
- [ ] **B5** `runme run --filename docs/ci/verify.md verify:help` — prints help text
  - Result:

```
# Dev log — will fail if no build-vm.log exists, but proves execution
runme run --filename docs/ci/dev.md dev:log
```
- [ ] **B6** `runme run --filename docs/ci/dev.md dev:log` — runs, expect file not found
  - Result:

```
# Dev kill — safe, just pkill + rm on nonexistent processes
runme run --filename docs/ci/dev.md dev:kill
```
- [ ] **B7** `runme run --filename docs/ci/dev.md dev:kill` — runs clean (no-op if no VM)
  - Result:

```
# Tmp clean — safe, removes temp dirs that probably don't exist
runme run --filename docs/ci/build.md _build:tmp:clean
```
- [ ] **B8** `runme run --filename docs/ci/build.md _build:tmp:clean` — runs clean
  - Result:

### Phase C: Full pipeline dry run

After all Phase A and B findings are recorded and fixes applied:

```
# The full CI pipeline — end-to-end
runme run --filename docs/ci/README.md ci:pipeline
```
- [ ] **C1** `runme run --filename docs/ci/README.md ci:pipeline` — full pipeline execution
  - Result:

### Findings Summary

| ID | Status | Notes |
|----|--------|-------|
| A1.1 | | |
| A1.2 | | |
| A1.3 | | |
| A1.4 | | |
| A1.5 | | |
| A1.6 | | |
| A1.7 | | |
| A1.8 | | |
| A1.9 | | |
| A1.10 | | |
| A1.11 | | |
| A1.12 | | |
| A1.13 | | |
| A1.14 | | |
| A1.15 | | |
| A1.16 | | |
| A1.17 | | |
| A1.18 | | |
| A1.19 | | |
| A1.20 | | |
| A1.21 | | |
| A1.22 | | |
| A1.23 | | |
| A1.24 | | |
| A2.1 | | |
| A2.2 | | |
| A2.3 | | |
| A2.4 | | |
| A3.1 | | |
| A3.2 | | |
| A3.3 | | |
| A3.4 | | |
| A3.5 | | |
| A4.1 | | |
| A4.2 | | |
| A5.1 | | |
| A5.2 | | |
| A5.3 | | |
| A5.4 | | |
| A6.1 | | |
| A6.2 | | |
| A7.1 | | |
| A7.2 | | |
| A7.3 | | |
| A7.4 | | |
| A7.5 | | |
| A7.6 | | |
| A7.7 | | |
| A7.8 | | |
| A8.1 | | |
| A8.2 | | |
| A8.3 | | |
| A8.4 | | |
| A8.5 | | |
| A8.6 | | |
| A8.7 | | |
| A8.8 | | |
| A8.9 | | |
| A8.10 | | |
| A9.1 | | |
| A9.2 | | |
| B1 | | |
| B2 | | |
| B3 | | |
| B4 | | |
| B5 | | |
| B6 | | |
| B7 | | |
| B8 | | |
| C1 | | |

---

## Table of Contents

- [1. Architecture](#1-architecture)
- [2. File Manifest](#2-file-manifest)
- [3. Runme Frontmatter Contract](#3-runme-frontmatter-contract)
- [4. Task Naming Convention](#4-task-naming-convention)
- [5. Cross-File Reference Map](#5-cross-file-reference-map)
- [6. Implementation Tasks](#6-implementation-tasks)
- [7. ADR Log](#7-adr-log)
- [8. Parity Verification Checklist](#8-parity-verification-checklist)

---

## 1. Architecture

### 1.1 Pipeline DAG

```text
ci:pipeline (README.md)
│
├── ci:preflight (inline in README.md, <1s)
│   ├── LD_LIBRARY_PATH + libstdc++.so
│   ├── docker daemon reachable
│   └── OVMF_CODE firmware present
│
├───────────────────────────────┐
│ PARALLEL (bash & + wait)      │
│                               │
▼                               ▼
build.md                        platform.md
┌───────────────────────┐       ┌───────────────────┐
│ build:clean            │       │ platform:up        │
│ build:preflight        │       │  mise compose:clean│
│ build:nix              │       │  mise compose:up   │
│ build:cloudinit        │       │  mise pulumi:up    │
│ build:img:reset        │       └───────────────────┘
│ build:vm:boot          │              │
│ build:vm:wait          │              │
│ build:vm:sync          │              │
│ build:vm:rebuild       │              │
│ build:vm:pki:test      │              │
│ build:vm:pki:status    │              │
│ build:vm:provenance    │              │
│ build:vm:gc            │              │
│ build:vm:zero          │              │
│ build:vm:halt          │              │
│ build:img:clean        │              │
│ build:img:compress     │              │
│ build:img:sparsify     │              │
│ build:tmp:clean        │              │
│ build:verify           │              │
│ build:container        │              │
└───────────────────────┘              │
        │                               │
        ├───────────────────────────────┘
        │ BARRIER (wait $BUILD_PID && wait $PLATFORM_PID)
        ▼
registry.md
┌────────────────────────┐
│ registry:trust          │ ← extract CA from k8s → docker + skopeo cert dirs
│ registry:login          │ ← docker login + skopeo login
└────────────────────────┘
        │
        ▼
push.md
┌────────────────────────┐
│ push:image              │ ← multi-tag skopeo copy + digest append to .konductor
└────────────────────────┘
        │
        ▼
registry.md
┌────────────────────────┐
│ registry:tags           │ ← confirm tags landed
└────────────────────────┘
        │
        ▼
validate.md
┌────────────────────────┐
│ validate:deploy         │ ← mise dev:k8s:konductor:up + validate
│ validate:services       │ ← port-forward + curl 4 web terminals
│ validate:runner         │ ← forgejo user/repo/push/dispatch/poll
└────────────────────────┘
        │
        ▼
═══ PIPELINE COMPLETE ═══
        │
        ▼ (manual gate, not in ci:pipeline)
promote.md
┌────────────────────────┐
│ promote:image           │ ← skopeo copy to docker.io / ghcr.io
└────────────────────────┘
```

### 1.2 Standalone Workflows (not called by ci:pipeline)

```text
dev.md — Human-in-the-loop development tools
┌────────────────────────┐
│ dev:clean               │ full build state reset
│ dev:start               │ boot VM (cloudinit → boot → wait)
│ dev:ssh                 │ ssh -p 2222 kc2admin@localhost
│ dev:stop                │ graceful VM shutdown
│ dev:rebase              │ nixos-rebuild switch --flake .#konductor
│ dev:vendor              │ vendor flake inputs for offline builds
│ dev:vendor:online       │ online refresh + vendor
│ dev:log                 │ view serial console log
│ dev:kill                │ force kill QEMU process
└────────────────────────┘

verify.md — Runs INSIDE a built Konductor VM (cwd: /opt/konductor)
┌────────────────────────┐
│ verify:help             │ usage text
│ verify:provenance       │ cat /.konductor
│ verify:source           │ git commit match
│ verify:flake            │ flake.lock sha256 match
│ verify:nix              │ nix derivation match
│ verify:all              │ all checks
│ verify:reproduce        │ full reproduction build + sha256 compare
└────────────────────────┘

platform.md — Also usable standalone by humans
┌────────────────────────┐
│ platform:up             │ same task CI calls
│ platform:down           │ destroy cluster
│ platform:status         │ kubectl + curl health check
└────────────────────────┘

registry.md — Also usable standalone by humans
┌────────────────────────┐
│ registry:trust          │ same task CI calls
│ registry:login          │ same task CI calls
│ registry:list           │ curl /v2/_catalog
│ registry:tags           │ curl /v2/.../tags/list
└────────────────────────┘
```

### 1.3 Execution Model

Every file is self-contained. No file ever calls a task in another file.
Only `README.md:ci:pipeline` orchestrates cross-file execution via `runme run --filename`.

```text
README.md → build.md     (one-way, returns)
README.md → platform.md  (one-way, returns)
README.md → registry.md  (one-way, returns)
README.md → push.md      (one-way, returns)
README.md → validate.md  (one-way, returns)
```

Within `build.md`, the public entry point `build:all` calls internal `_build:*` tasks
via `runme run --filename "$THIS_FILE" _build:phase`. This is intra-file only.

Within `dev.md`, tasks that need OCI build phases (cloudinit, vm:boot, vm:wait, vm:halt)
carry their own inline implementation — no cross-file delegation.

---

## 2. File Manifest

| File | Lines (est.) | Tasks | Role |
|------|-------------|-------|------|
| `README.md` | ~250 | `ci:pipeline` | Sole orchestrator + pipeline docs + DAG |
| `build.md` | ~850 | 22 (1 public + 21 internal) | Source → sealed QCOW2 → OCI containerDisk |
| `platform.md` | ~80 | 3 | Cluster lifecycle (Talos + Pulumi) |
| `registry.md` | ~120 | 4 | Registry trust, auth, inspection |
| `push.md` | ~80 | 1 | Multi-tag push to local registry |
| `validate.md` | ~350 | 3 | KubeVirt deploy + service checks + runner test |
| `promote.md` | ~150 | 1 | Manual gate → public registry copy |
| `verify.md` | ~250 | 7 | Build verification (runs inside VM) |
| `dev.md` | ~300 | 9 | Developer workflow tools |

**Total: 9 files, ~2430 lines, 51 tasks**

---

## 3. Runme Frontmatter Contract

Every `.md` file in `docs/ci/` uses this frontmatter pattern:

```yaml
---
cwd: ../../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: <file-specific-tags>
runme:
  version: v3
---
```

**Critical:** `cwd: ../../..` resolves to workspace root from `docs/ci/`. This is
the same pattern as the prior art (`docs/developer_guide/qcow2/` used `cwd: ../../..`
to reach workspace root from 3 levels deep). `docs/ci/` is only 2 levels deep, so
the correct value is `cwd: ../..`.

> **ADR-001:** `cwd` must be `../..` not `../../..`. The prior art was 3 dirs deep
> (`docs/developer_guide/qcow2/`), the new location is 2 dirs deep (`docs/ci/`).
> Every `cwd` in every file changes. Every `OCI_BUILD_FILE` and `QCOW2_BUILD_FILE`
> variable that referenced the old path is eliminated entirely.

**Exception:** `verify.md` keeps `cwd: /opt/konductor` and `shell: bash` because it
runs inside the built VM, not the build host.

---

## 4. Task Naming Convention

### CI Pipeline tasks (called by ci:pipeline)

| File | Namespace | Public tasks | Internal tasks |
|------|-----------|-------------|----------------|
| README.md | `ci:` | `ci:pipeline` | — |
| build.md | `build:` | `build:all` | `_build:clean`, `_build:preflight`, `_build:nix`, `_build:cloudinit`, `_build:img:reset`, `_build:vm:boot`, `_build:vm:wait`, `_build:vm:sync`, `_build:vm:rebuild`, `_build:vm:pki:test`, `_build:vm:pki:status`, `_build:vm:provenance`, `_build:vm:gc`, `_build:vm:zero`, `_build:vm:halt`, `_build:img:clean`, `_build:img:compress`, `_build:img:sparsify`, `_build:tmp:clean`, `_build:verify`, `_build:container` |
| platform.md | `platform:` | `platform:up`, `platform:down`, `platform:status` | — |
| registry.md | `registry:` | `registry:trust`, `registry:login`, `registry:list`, `registry:tags` | — |
| push.md | `push:` | `push:image` | — |
| validate.md | `validate:` | `validate:deploy`, `validate:services`, `validate:runner` | — |
| promote.md | `promote:` | `promote:image` | — |

### Standalone tasks (never called by ci:pipeline)

| File | Namespace | Tasks |
|------|-----------|-------|
| dev.md | `dev:` | `dev:clean`, `dev:start`, `dev:ssh`, `dev:stop`, `dev:rebase`, `dev:vendor`, `dev:vendor:online`, `dev:log`, `dev:kill` |
| verify.md | `verify:` | `verify:help`, `verify:provenance`, `verify:source`, `verify:flake`, `verify:nix`, `verify:all`, `verify:reproduce` |

### Naming rules

- Public entry points: `namespace:action` (e.g., `build:all`, `push:image`)
- Internal phases: `_namespace:phase` (e.g., `_build:nix`, `_build:vm:boot`)
- Internal tasks get `excludeFromRunAll: true` — they are called only by their file's public entry point
- All tasks get `excludeFromRunAll: true` — nothing should run from `runme run --all`

---

## 5. Cross-File Reference Map

### Prior art references that must be rewritten

Every instance of these patterns in bash code blocks must be eliminated:

| Old pattern | New pattern | Where it appeared |
|------------|------------|-------------------|
| `OCI_BUILD_FILE="${OCI_BUILD_FILE:-docs/developer_guide/qcow2/OCI.md}"` | Eliminated. Tasks are local to their file. | BUILD.md: 8 tasks, OCI.md: 4 tasks |
| `QCOW2_BUILD_FILE="${QCOW2_BUILD_FILE:-docs/developer_guide/qcow2/BUILD.md}"` | Eliminated. `ci:pipeline` uses literal paths. | BUILD.md: `build:qcow2:all` |
| `runme run --filename "$OCI_BUILD_FILE"` | `runme run --filename "$BUILD_FILE"` (intra-file) or eliminated | BUILD.md: 8 calls, OCI.md: 4 calls |
| `runme run --filename "$QCOW2_BUILD_FILE"` | `runme run --filename "$CI_DIR/<file>.md"` (README.md only) | BUILD.md: `build:qcow2:all` |
| `--direnv=true --load-env=false` | Preserved on all `runme run` calls — this is load-bearing | All cross-file calls |

### New cross-file calls (README.md only)

```bash
CI_DIR="docs/ci"

# Parallel phase
runme run --direnv=true --load-env=false --filename "$CI_DIR/build.md" build:all &
runme run --direnv=true --load-env=false --filename "$CI_DIR/platform.md" platform:up &
wait ...

# Sequential phases
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:trust
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:login
runme run --direnv=true --load-env=false --filename "$CI_DIR/push.md" push:image
runme run --direnv=true --load-env=false --filename "$CI_DIR/registry.md" registry:tags
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:deploy
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:services
runme run --direnv=true --load-env=false --filename "$CI_DIR/validate.md" validate:runner
```

### Intra-file calls (build.md only)

`build:all` calls each `_build:*` phase via:
```bash
BUILD_FILE="docs/ci/build.md"
for phase in "${PHASES[@]}"; do
    runme run --direnv=true --load-env=false --filename "$BUILD_FILE" "$phase"
done
```

The `--load-env=false` on internal phases prevents `.env` double-loading. The
`--load-env=true` exception is `_build:container` which needs nix devshell env
(matching prior art `oci:container` which used `--load-env=true`).

### Intra-file calls (dev.md)

`dev:start` needs cloudinit + vm:boot + vm:wait. These are NOT cross-file calls.
The bash is inlined directly into `dev:start`, or `dev.md` carries its own internal
`_dev:cloudinit`, `_dev:vm:boot`, `_dev:vm:wait`, `_dev:vm:halt` tasks.

> **ADR-002:** `dev.md` duplicates the cloudinit/boot/wait/halt bash from `build.md`.
> This is intentional. The alternative (cross-file calls from dev.md → build.md) violates
> the "no file calls another file except README.md" rule. The duplication is ~120 lines
> of stable, rarely-changing QEMU/cloud-init config. The cost of duplication is lower
> than the cost of coupling.

> **ADR-003 (alternative to ADR-002):** If duplication is unacceptable, `dev:start` can
> call `build.md` phases via `runme run --filename docs/ci/build.md _build:cloudinit` etc.
> This makes dev.md depend on build.md, which is acceptable since dev.md is never called
> by CI. Decision: **Implement ADR-003** — dev.md calls build.md internal tasks. This
> keeps a single source of truth for QEMU boot config while only allowing the non-CI
> file to have a cross-file dependency.

---

## 6. Implementation Tasks

### Phase 0: Scaffolding

#### TASK-000: Create directory and frontmatter templates
- [x] `mkdir -p docs/ci`
- [ ] Determine exact `cwd` value by testing `runme run` from `docs/ci/` with `cwd: ../..`
- [ ] Create this file (you're reading it)

**Acceptance:** `ls docs/ci/` shows directory exists.

---

### Phase 1: build.md (the critical path — largest, most complex file)

#### TASK-100: Write build.md frontmatter + docs header
- [ ] Frontmatter: `cwd: ../..`, `shell: /run/current-system/sw/bin/bash`, `skipPrompts: true`, `tag: scope:ci,target:qcow2`, `runme: version: v3`
- [ ] Title, contents TOC, environment variables section (from OCI.md lines 44-62)
- [ ] Task reference table (all 22 tasks with descriptions)

**Source parity:** OCI.md lines 1-88

---

#### TASK-101: Write build:all entry point
- [ ] Public entry point that orchestrates all `_build:*` phases in order
- [ ] Phase list must exactly match: `_build:clean` through `_build:container`
- [ ] Uses `runme run --direnv=true --load-env=false --filename "$BUILD_FILE"` for each phase
- [ ] Exception: `_build:container` uses `--load-env=true`
- [ ] Banner output matching prior art style

**Source parity:** OCI.md `oci:build` (lines 93-121) + `oci:image` (lines 129-161)

**Critical detail:** The prior `oci:build` called `oci:clean`, `oci:image`, `oci:container`.
And `oci:image` looped through 19 `_oci:*` phases. The new `build:all` flattens this into
one loop: clean → preflight → nix → ... → verify → container. No nested orchestrators.

```
Prior art call chain:       New call chain:
oci:build                   build:all
  → oci:clean                 → _build:clean
  → oci:image                 → _build:preflight
    → _oci:preflight          → _build:nix
    → _oci:nix                → _build:cloudinit
    → _oci:cloudinit          → ... (15 more)
    → ... (16 more)           → _build:verify
  → oci:container             → _build:container
```

---

#### TASK-102: Write _build:clean
- [ ] Exact bash from OCI.md `oci:clean` (lines 219-227)
- [ ] Task metadata: `"name":"_build:clean","excludeFromRunAll":"true","tag":"type:destructive"`

**Source parity:** OCI.md lines 219-227. Zero changes to bash body.

---

#### TASK-103: Write _build:preflight
- [ ] Exact bash from OCI.md `_oci:preflight` (lines 504-681)
- [ ] This is ~180 lines of environment validation — every check preserved
- [ ] Sections: clean state, required binaries, versions, flake metadata, flake outputs, runtime environment (OVMF, LD_LIBRARY_PATH, DOCKER_HOST, Docker daemon, DOCKER_BUILDKIT), SSH key, KVM access, port availability, resources
- [ ] Task metadata: `"name":"_build:preflight"`

**Source parity:** OCI.md lines 504-681. Zero changes to bash body.

---

#### TASK-104: Write _build:nix
- [ ] Exact bash from OCI.md `_oci:nix` (lines 689-738)
- [ ] Includes: SKIP_NIX_BUILD check, vendored inputs check, forgejo-runner-src update, `nix build .#qcow2`, derivation hash capture, writable overlay creation
- [ ] Task metadata: `"name":"_build:nix","tag":"requires:nix"`

**Source parity:** OCI.md lines 689-738. Zero changes to bash body.

---

#### TASK-105: Write _build:cloudinit
- [ ] Exact bash from OCI.md `_oci:cloudinit` (lines 746-862)
- [ ] This is ~115 lines including the full cloud-init user-data template with all 4 users (PLACEHOLDER_USER, kc2, kc2admin, runner), write_files, runcmd (network preflight, service status logging), proxy detection, genisoimage
- [ ] Task metadata: `"name":"_build:cloudinit"`

**Source parity:** OCI.md lines 746-862. Zero changes to bash body.

---

#### TASK-106: Write _build:img:reset
- [ ] Exact bash from OCI.md `_oci:img:reset` (lines 870-886)
- [ ] Task metadata: `"name":"_build:img:reset","tag":"requires:guestfs"`

**Source parity:** OCI.md lines 870-886. Zero changes to bash body.

---

#### TASK-107: Write _build:vm:boot
- [ ] Exact bash from OCI.md `_oci:vm:boot` (lines 894-942)
- [ ] Full QEMU command with: q35+kvm, pflash OVMF, virtio drive, cloud-init cdrom, user-mode networking with 3 port forwards, virtio-rng, 9p host+nixstore mounts, daemonize, serial log
- [ ] Task metadata: `"name":"_build:vm:boot","tag":"requires:kvm"`

**Source parity:** OCI.md lines 894-942. Zero changes to bash body.

---

#### TASK-108: Write _build:vm:wait
- [ ] Exact bash from OCI.md `_oci:vm:wait` (lines 950-977)
- [ ] SSH poll loop with configurable timeout (300s default), retry counting
- [ ] Task metadata: `"name":"_build:vm:wait","tag":"duration:slow"`

**Source parity:** OCI.md lines 950-977. Zero changes to bash body.

---

#### TASK-109: Write _build:vm:sync
- [ ] Exact bash from OCI.md `_oci:vm:sync` (lines 985-1029)
- [ ] git bundle create + scp + clone + _sources rsync + dirty check + chown
- [ ] Task metadata: `"name":"_build:vm:sync"`

**Source parity:** OCI.md lines 985-1029. Zero changes to bash body.

---

#### TASK-110: Write _build:vm:rebuild
- [ ] Exact bash from OCI.md `_oci:vm:rebuild` (lines 1043-1076)
- [ ] Override inputs from _sources, stop cloud-init, nixos-rebuild switch with proxy, cache 3 devshells (default, full, konductor)
- [ ] Task metadata: `"name":"_build:vm:rebuild","tag":"duration:slow"`

**Source parity:** OCI.md lines 1043-1076. Zero changes to bash body.

---

#### TASK-111: Write _build:vm:pki:test
- [ ] Exact bash from OCI.md `_oci:vm:pki:test` (lines 1084-1096)
- [ ] Task metadata: `"name":"_build:vm:pki:test"`

**Source parity:** OCI.md lines 1084-1096. Zero changes to bash body.

---

#### TASK-112: Write _build:vm:pki:status
- [ ] Exact bash from OCI.md `_oci:vm:pki:status` (lines 1104-1114)
- [ ] Task metadata: `"name":"_build:vm:pki:status"`

**Source parity:** OCI.md lines 1104-1114. Zero changes to bash body.

---

#### TASK-113: Write _build:vm:provenance
- [ ] Exact bash from OCI.md `_oci:vm:provenance` (lines 1122-1203)
- [ ] ~80 lines: git provenance, nix provenance, hardware identity, tag list construction, SSH tee to /.konductor, PKI regeneration, copy to host, fastfetch
- [ ] Task metadata: `"name":"_build:vm:provenance"`

**Source parity:** OCI.md lines 1122-1203. Zero changes to bash body.

---

#### TASK-114: Write _build:vm:gc
- [ ] Exact bash from OCI.md `_oci:vm:gc` (lines 1211-1219)
- [ ] Task metadata: `"name":"_build:vm:gc"`

**Source parity:** OCI.md lines 1211-1219. Zero changes to bash body.

---

#### TASK-115: Write _build:vm:zero
- [ ] Exact bash from OCI.md `_oci:vm:zero` (lines 1227-1232)
- [ ] Task metadata: `"name":"_build:vm:zero","tag":"duration:slow"`

**Source parity:** OCI.md lines 1227-1232. Zero changes to bash body.

---

#### TASK-116: Write _build:vm:halt
- [ ] Exact bash from OCI.md `_oci:vm:halt` (lines 1240-1254)
- [ ] Task metadata: `"name":"_build:vm:halt"`

**Source parity:** OCI.md lines 1240-1254. Zero changes to bash body.

---

#### TASK-117: Write _build:img:clean
- [ ] Exact bash from OCI.md `_oci:img:clean` (lines 1262-1302)
- [ ] ~40 lines: guestmount, remove host keys/machine-id/cloud-init/journal, remove ALL credentials from all home dirs, remove build-time cloud-init user (with passwd/shadow/group cleanup)
- [ ] Task metadata: `"name":"_build:img:clean","tag":"requires:guestfs"`

**Source parity:** OCI.md lines 1262-1302. Zero changes to bash body.

---

#### TASK-118: Write _build:img:compress
- [ ] Exact bash from OCI.md `_oci:img:compress` (lines 1312-1326)
- [ ] SKIP_COMPRESS support, core count cap at 16, zstd compression
- [ ] Task metadata: `"name":"_build:img:compress","tag":"duration:slow"`

**Source parity:** OCI.md lines 1312-1326. Zero changes to bash body.

---

#### TASK-119: Write _build:img:sparsify
- [ ] Exact bash from OCI.md `_oci:img:sparsify` (lines 1334-1348)
- [ ] Task metadata: `"name":"_build:img:sparsify","tag":"duration:slow,requires:guestfs"`

**Source parity:** OCI.md lines 1334-1348. Zero changes to bash body.

---

#### TASK-120: Write _build:tmp:clean
- [ ] Exact bash from OCI.md `_oci:tmp:clean` (lines 1356-1359)
- [ ] Task metadata: `"name":"_build:tmp:clean"`

**Source parity:** OCI.md lines 1356-1359. Zero changes to bash body.

---

#### TASK-121: Write _build:verify
- [ ] Exact bash from OCI.md `_oci:verify` (lines 1367-1380)
- [ ] Appends image_sha256 and image_size to .konductor
- [ ] Task metadata: `"name":"_build:verify","tag":"type:readonly"`

**Source parity:** OCI.md lines 1367-1380. Zero changes to bash body.

---

#### TASK-122: Write _build:container
- [ ] Exact bash from OCI.md `oci:container` (lines 169-209)
- [ ] nix print-dev-env, docker buildx build, tag application from .konductor TOML
- [ ] Task metadata: `"name":"_build:container","excludeFromRunAll":"true","tag":"requires:docker"`
- [ ] **Note:** This is the one phase that used `--load-env=true` in prior art

**Source parity:** OCI.md lines 169-209. Zero changes to bash body.

---

### Phase 2: platform.md

#### TASK-200: Write platform.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci,scope:cluster`
- [ ] 3 tasks: `platform:up`, `platform:down`, `platform:status`
- [ ] Documentation sections for each task

**Source parity:**
- `platform:up` ← BUILD.md `cluster:up` (lines 361-370). Exact bash.
- `platform:down` ← BUILD.md `cluster:down` (lines 380-382). Exact bash.
- `platform:status` ← BUILD.md `cluster:status` (lines 390-395). Exact bash.

---

### Phase 3: registry.md

#### TASK-300: Write registry.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci,scope:registry`
- [ ] 4 tasks: `registry:trust`, `registry:login`, `registry:list`, `registry:tags`
- [ ] Documentation sections for each task

**Source parity:**
- `registry:trust` ← BUILD.md lines 416-447. Exact bash.
- `registry:login` ← BUILD.md lines 457-473. Exact bash.
- `registry:list` ← BUILD.md lines 481-485. Exact bash.
- `registry:tags` ← BUILD.md lines 493-498. Exact bash.

---

### Phase 4: push.md

#### TASK-400: Write push.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci`
- [ ] 1 task: `push:image`
- [ ] Documentation section

**Source parity:** `push:image` ← BUILD.md `build:qcow2:push` (lines 588-631). Exact bash.

---

### Phase 5: validate.md

#### TASK-500: Write validate.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci,scope:validation`
- [ ] 3 tasks: `validate:deploy`, `validate:services`, `validate:runner`
- [ ] Documentation sections for each task

**Source parity:**
- `validate:deploy` ← BUILD.md `build:qcow2:validate` (lines 669-673). Exact bash.
- `validate:services` ← BUILD.md `build:qcow2:validate-services` (lines 692-753). Exact bash.
- `validate:runner` ← BUILD.md `build:qcow2:runner-test` (lines 782-909). Exact bash.

---

### Phase 6: promote.md

#### TASK-600: Write promote.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci,scope:promotion`
- [ ] 1 task: `promote:image`
- [ ] Full documentation including auth flow for docker.io and ghcr.io

**Source parity:** `promote:image` ← BUILD.md `build:qcow2:promote` (lines 945-1051). Exact bash.

---

### Phase 7: verify.md

#### TASK-700: Write verify.md complete
- [ ] Frontmatter: `cwd: /opt/konductor`, `shell: bash`, `tag: scope:verify`
- [ ] 7 tasks: `verify:help`, `verify:provenance`, `verify:source`, `verify:flake`, `verify:nix`, `verify:all`, `verify:reproduce`
- [ ] `verify:reproduce` must update its `QCOW2_BUILD_FILE` reference to point to `docs/ci/build.md`

**Source parity:** VERIFY.md lines 1-305. All bash preserved.

**Critical change in `verify:reproduce`:**
```bash
# OLD (VERIFY.md line 265):
export QCOW2_BUILD_FILE=docs/developer_guide/qcow2/BUILD.md
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:image

# NEW:
export BUILD_FILE=docs/ci/build.md
runme run --filename "$BUILD_FILE" build:all
```

> **ADR-004:** `verify:reproduce` originally called `build:qcow2:image` (image only, no container).
> In the new structure, the equivalent is running `build:all` which includes the container phase.
> For pure reproduction verification, only the QCOW2 image matters (sha256 comparison).
> Decision: Create a `build:image` public entry point in build.md that runs phases through
> `_build:verify` but stops before `_build:container`. This gives verify:reproduce an
> exact equivalent without forcing unnecessary container build during reproduction testing.

---

### Phase 8: dev.md

#### TASK-800: Write dev.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:dev`
- [ ] 9 tasks: `dev:clean`, `dev:start`, `dev:ssh`, `dev:stop`, `dev:rebase`, `dev:vendor`, `dev:vendor:online`, `dev:log`, `dev:kill`

**Source parity (per ADR-003, dev.md calls build.md for VM lifecycle):**
- `dev:clean` ← OCI.md `oci:clean` (lines 219-227). Exact bash.
- `dev:start` ← BUILD.md `build:qcow2:start` (lines 1076-1101). Rewired: calls `_build:cloudinit`, `_build:vm:boot`, `_build:vm:wait` via `runme run --filename docs/ci/build.md`
- `dev:ssh` ← BUILD.md `build:qcow2:ssh` (line 1112). Exact bash.
- `dev:stop` ← BUILD.md `build:qcow2:stop` (lines 1121-1124). Rewired: calls `_build:vm:halt` via `runme run --filename docs/ci/build.md`
- `dev:rebase` ← BUILD.md `build:qcow2:rebase` (lines 1137-1140). Exact bash.
- `dev:vendor` ← OCI.md `oci:vendor:inputs` (lines 280-382). Exact bash.
- `dev:vendor:online` ← OCI.md `oci:vendor:inputs:online` (lines 391-492). Exact bash. **Must update internal `runme run oci:vendor:inputs` call to `runme run --filename docs/ci/dev.md dev:vendor`**
- `dev:log` ← OCI.md `oci:debug:log` (lines 1390-1392). Exact bash.
- `dev:kill` ← OCI.md `oci:vm:kill` (lines 1400-1403). Exact bash.

---

### Phase 9: README.md (the orchestrator)

#### TASK-900: Write README.md complete
- [ ] Frontmatter: `cwd: ../..`, `tag: scope:ci`
- [ ] Pipeline architecture diagram (the DAG from section 1.1)
- [ ] Quick start section
- [ ] Task reference table (all tasks across all files)
- [ ] `ci:pipeline` task with:
  - Inline preflight (LD_LIBRARY_PATH, docker, OVMF — 3 checks)
  - Parallel `build:all` + `platform:up` via `&` + `wait`
  - Sequential: `registry:trust` → `registry:login` → `push:image` → `registry:tags` → `validate:deploy` → `validate:services` → `validate:runner`
  - Completion banner with promotion instructions
- [ ] Workflow examples section
- [ ] Troubleshooting section (from BUILD.md lines 1388-1499)
- [ ] Output artifacts documentation (from BUILD.md lines 1251-1318)
- [ ] Supply chain provenance documentation (from BUILD.md lines 1322-1385)

**Source parity for ci:pipeline:** BUILD.md `build:qcow2:all` (lines 1166-1247). Rewritten
with parallel execution but same phases, same error handling, same output format.

---

### Phase 10: Validation

#### TASK-1000: Verify runme task listing for every file
- [ ] `runme list --filename docs/ci/README.md` — shows `ci:pipeline`
- [ ] `runme list --filename docs/ci/build.md` — shows `build:all`, `build:image`, all `_build:*`
- [ ] `runme list --filename docs/ci/platform.md` — shows `platform:up`, `platform:down`, `platform:status`
- [ ] `runme list --filename docs/ci/registry.md` — shows `registry:trust`, `registry:login`, `registry:list`, `registry:tags`
- [ ] `runme list --filename docs/ci/push.md` — shows `push:image`
- [ ] `runme list --filename docs/ci/validate.md` — shows `validate:deploy`, `validate:services`, `validate:runner`
- [ ] `runme list --filename docs/ci/promote.md` — shows `promote:image`
- [ ] `runme list --filename docs/ci/verify.md` — shows all `verify:*` tasks
- [ ] `runme list --filename docs/ci/dev.md` — shows all `dev:*` tasks

---

#### TASK-1001: Cross-reference every original task to its new location
- [ ] Build the old→new mapping table and verify no task is missing
- [ ] Confirm every bash code block from BUILD.md, OCI.md, VERIFY.md has a home
- [ ] Confirm example/troubleshooting blocks from BUILD.md are in README.md docs

---

#### TASK-1002: Verify no residual references to old paths
- [ ] `grep -r "developer_guide/qcow2" docs/ci/` returns empty (except verify.md ADR-004 comments if any)
- [ ] `grep -r "OCI_BUILD_FILE" docs/ci/` returns empty
- [ ] `grep -r "QCOW2_BUILD_FILE" docs/ci/` returns empty
- [ ] `grep -r "oci:" docs/ci/` returns empty (all `oci:*` tasks renamed)
- [ ] `grep -r "build:qcow2:" docs/ci/` returns empty (all `build:qcow2:*` tasks renamed)

---

#### TASK-1003: Verify dev:vendor:online internal runme call
- [ ] The bash in `dev:vendor:online` contains `runme run oci:vendor:inputs` (OCI.md line 489)
- [ ] This MUST be rewritten to `runme run --filename docs/ci/dev.md dev:vendor`
- [ ] Failure to catch this = runtime break when old path is deleted

---

#### TASK-1004: Verify verify:reproduce build file reference
- [ ] The bash in `verify:reproduce` references `docs/developer_guide/qcow2/BUILD.md` (VERIFY.md line 265)
- [ ] This MUST be rewritten per ADR-004
- [ ] Failure to catch this = runtime break when old path is deleted

---

## 7. ADR Log

### ADR-001: cwd depth change
**Context:** Prior art at `docs/developer_guide/qcow2/` used `cwd: ../../..` (3 levels).
New location `docs/ci/` is 2 levels deep.
**Decision:** All frontmatter uses `cwd: ../..`.
**Consequence:** Every file's cwd is correct without runtime path resolution tricks.

### ADR-002: dev.md VM lifecycle duplication (SUPERSEDED by ADR-003)
**Context:** dev:start/stop need cloudinit/boot/wait/halt implementations.
**Decision:** Duplicate ~120 lines of bash in dev.md.
**Status:** Superseded. See ADR-003.

### ADR-003: dev.md calls build.md internal tasks
**Context:** dev:start/stop need cloudinit/boot/wait/halt. Duplication is ~120 lines.
**Decision:** dev.md calls `_build:*` tasks via `runme run --filename docs/ci/build.md`.
This is the only non-README file with cross-file calls. Acceptable because dev.md is
never called by CI — it's a human-only tool.
**Consequence:** Single source of truth for QEMU boot config. dev.md depends on build.md.

### ADR-004: build:image entry point for verify:reproduce
**Context:** `verify:reproduce` needs to build QCOW2 without container packaging.
Prior art called `build:qcow2:image` which ran OCI.md phases through `_oci:verify`.
**Decision:** Add `build:image` public entry point in build.md that runs `_build:clean`
through `_build:verify` (skipping `_build:container`). This gives verify:reproduce
exact parity.
**Consequence:** build.md has 2 public entry points: `build:all` (full) and `build:image` (QCOW2 only).

### ADR-005: (reserved for implementation discoveries)

---

## 8. Parity Verification Checklist

### BUILD.md tasks (22 → all accounted for)

| Original task | New location | New name | Status |
|--------------|-------------|----------|--------|
| `build:qcow2:all` | README.md | `ci:pipeline` | [ ] |
| `build:qcow2:publish` | build.md | `build:all` (absorbed) | [ ] |
| `build:qcow2:image` | build.md | `build:image` | [ ] |
| `build:qcow2:container` | build.md | `_build:container` | [ ] |
| `build:qcow2:clean` | build.md | `_build:clean` (+ dev.md `dev:clean`) | [ ] |
| `build:qcow2:push` | push.md | `push:image` | [ ] |
| `build:qcow2:validate` | validate.md | `validate:deploy` | [ ] |
| `build:qcow2:validate-services` | validate.md | `validate:services` | [ ] |
| `build:qcow2:runner-test` | validate.md | `validate:runner` | [ ] |
| `build:qcow2:promote` | promote.md | `promote:image` | [ ] |
| `build:qcow2:start` | dev.md | `dev:start` | [ ] |
| `build:qcow2:ssh` | dev.md | `dev:ssh` | [ ] |
| `build:qcow2:stop` | dev.md | `dev:stop` | [ ] |
| `build:qcow2:rebase` | dev.md | `dev:rebase` | [ ] |
| `cluster:up` | platform.md | `platform:up` | [ ] |
| `cluster:down` | platform.md | `platform:down` | [ ] |
| `cluster:status` | platform.md | `platform:status` | [ ] |
| `registry:trust` | registry.md | `registry:trust` | [ ] |
| `registry:login` | registry.md | `registry:login` | [ ] |
| `registry:list` | registry.md | `registry:list` | [ ] |
| `registry:tags` | registry.md | `registry:tags` | [ ] |

### OCI.md tasks (30 → all accounted for)

| Original task | New location | New name | Status |
|--------------|-------------|----------|--------|
| `oci:build` | build.md | `build:all` (absorbed orchestrator) | [ ] |
| `oci:image` | build.md | `build:image` (absorbed orchestrator) | [ ] |
| `oci:container` | build.md | `_build:container` | [ ] |
| `oci:clean` | build.md | `_build:clean` | [ ] |
| `oci:start` | dev.md | `dev:start` (deduplicated) | [ ] |
| `oci:ssh` | dev.md | `dev:ssh` (deduplicated) | [ ] |
| `oci:stop` | dev.md | `dev:stop` (deduplicated) | [ ] |
| `oci:vendor:inputs` | dev.md | `dev:vendor` | [ ] |
| `oci:vendor:inputs:online` | dev.md | `dev:vendor:online` | [ ] |
| `oci:debug:log` | dev.md | `dev:log` | [ ] |
| `oci:vm:kill` | dev.md | `dev:kill` | [ ] |
| `_oci:preflight` | build.md | `_build:preflight` | [ ] |
| `_oci:nix` | build.md | `_build:nix` | [ ] |
| `_oci:cloudinit` | build.md | `_build:cloudinit` | [ ] |
| `_oci:img:reset` | build.md | `_build:img:reset` | [ ] |
| `_oci:vm:boot` | build.md | `_build:vm:boot` | [ ] |
| `_oci:vm:wait` | build.md | `_build:vm:wait` | [ ] |
| `_oci:vm:sync` | build.md | `_build:vm:sync` | [ ] |
| `_oci:vm:rebuild` | build.md | `_build:vm:rebuild` | [ ] |
| `_oci:vm:pki:test` | build.md | `_build:vm:pki:test` | [ ] |
| `_oci:vm:pki:status` | build.md | `_build:vm:pki:status` | [ ] |
| `_oci:vm:provenance` | build.md | `_build:vm:provenance` | [ ] |
| `_oci:vm:gc` | build.md | `_build:vm:gc` | [ ] |
| `_oci:vm:zero` | build.md | `_build:vm:zero` | [ ] |
| `_oci:vm:halt` | build.md | `_build:vm:halt` | [ ] |
| `_oci:img:clean` | build.md | `_build:img:clean` | [ ] |
| `_oci:img:compress` | build.md | `_build:img:compress` | [ ] |
| `_oci:img:sparsify` | build.md | `_build:img:sparsify` | [ ] |
| `_oci:tmp:clean` | build.md | `_build:tmp:clean` | [ ] |
| `_oci:verify` | build.md | `_build:verify` | [ ] |

### VERIFY.md tasks (7 → all accounted for)

| Original task | New location | New name | Status |
|--------------|-------------|----------|--------|
| `verify:konductor` | verify.md | `verify:help` | [ ] |
| `verify:konductor:provenance` | verify.md | `verify:provenance` | [ ] |
| `verify:konductor:source` | verify.md | `verify:source` | [ ] |
| `verify:konductor:flake` | verify.md | `verify:flake` | [ ] |
| `verify:konductor:nix` | verify.md | `verify:nix` | [ ] |
| `verify:konductor:all` | verify.md | `verify:all` | [ ] |
| `verify:konductor:reproduce` | verify.md | `verify:reproduce` | [ ] |

### BUILD.md documentation sections (must land in README.md)

| Section | Lines | New location | Status |
|---------|-------|-------------|--------|
| Overview | 38-56 | README.md | [ ] |
| Pipeline Architecture diagram | 59-115 | README.md (updated DAG) | [ ] |
| Quick Start | 122-161 | README.md | [ ] |
| Task Reference tables | 164-218 | README.md (updated names) | [ ] |
| Workflow examples | 220-337 | README.md | [ ] |
| Output Artifacts | 1251-1318 | README.md | [ ] |
| Supply Chain Provenance | 1322-1385 | README.md | [ ] |
| Troubleshooting | 1388-1499 | README.md | [ ] |

---

## Implementation Order

```text
1. build.md        ← Critical path. Largest file. Do first.
2. platform.md     ← Small, independent. Quick win.
3. registry.md     ← Small, independent. Quick win.
4. push.md         ← Small, depends on build.md + registry.md existing.
5. validate.md     ← Medium, independent.
6. promote.md      ← Small, independent.
7. verify.md       ← Small, different cwd. Independent.
8. dev.md          ← Medium, depends on build.md (ADR-003 cross-file calls).
9. README.md       ← Last. Orchestrator needs all files to exist.
10. Validation     ← runme list + grep verification.
```
