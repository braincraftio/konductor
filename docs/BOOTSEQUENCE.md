# Konductor Boot Sequence Architecture

**Version:** 1.0
**Last Updated:** 2026-02-04
**Status:** Design Specification

---

## Overview

This document defines the systemd service ordering, dependency chain, and validation gate architecture for Konductor QCOW2 VMs. The design ensures deterministic boot behavior with conditional strictness for production vs development workflows.

---

## Design Principles

1. **Serial Console is the Trusted Pathway** - All boot validation output goes to `/dev/ttyS0`, captured by KubeVirt pod log collector and shipped to upstream log analysis.

2. **Exit Code IS the Gate** - `konductor.service` exit code determines whether dependent services start. Strictness logic is inside the service, not in systemd unit configuration.

3. **Conditional Strictness** - `strict=true` blocks on validation failure; `strict=false` warns loudly but allows degraded operation.

4. **Static Dependencies, Dynamic Behavior** - Systemd unit files are static; runtime behavior is controlled by the `strict` flag in `/.konductor`.

---

## Boot Phase Timeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: PRE-NETWORK (local-fs.target)                                      │
│ Time: 0-2s                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ① cloud-init-local.service                                                 │
│     ├─ Reads NoCloud datasource (seed.iso)                                  │
│     ├─ Sets hostname from meta-data                                         │
│     ├─ Writes early files (write_files module)                              │
│     ├─ Runs bootcmd                                                         │
│     └─ BEFORE: systemd-networkd.service                                     │
│                                                                             │
│  ② /nix/.host-store automount (if virtiofs available)                       │
│     ├─ Triggered on first access by nix substituter                         │
│     └─ Provides read-only host nix store as local binary cache              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: NETWORK INITIALIZATION                                             │
│ Time: 2-5s                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ③ systemd-networkd.service                                                 │
│     ├─ Configures network interfaces (enp1s0, enp2s0, br0)                  │
│     ├─ Applies cloud-init network config (version 1 or 2)                   │
│     └─ Gets DHCP lease or applies static config                             │
│                                                                             │
│  ④ systemd-networkd-wait-online.service                                     │
│     └─ Waits for at least one interface to be configured                    │
│                                                                             │
│  ⑤ network-online.target                                                    │
│     └─ Signals: network is fully configured and routable                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: CLOUD-INIT MAIN                                                    │
│ Time: 5-8s                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑥ cloud-init.service                                                       │
│     ├─ AFTER: network-online.target, cloud-init-local.service               │
│     ├─ BEFORE: sshd.service, sshd-keygen.service                            │
│     ├─ Fetches instance metadata                                            │
│     ├─ Creates users/groups (users_groups module)                           │
│     ├─ Configures SSH keys (ssh module)                                     │
│     ├─ Runs growpart/resizefs                                               │
│     └─ Generates SSH host keys                                              │
│                                                                             │
│  ⑦ sshd.service                                                             │
│     ├─ AFTER: cloud-init.service                                            │
│     └─ SSH access now available                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: STORAGE MOUNTS                                                     │
│ Time: 5-10s (parallel with Phase 3)                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑧ konductor-mount@<device>.service (template instances)                    │
│     ├─ AFTER: local-fs.target                                               │
│     ├─ BEFORE: cloud-config.service                                         │
│     ├─ Mounts virtio block devices by serial ID                             │
│     ├─ Creates mount point if needed                                        │
│     ├─ Sets ownership (kc2:kc2) and permissions (2775)                      │
│     └─ Instances:                                                           │
│        ├─ konductor-mount@workspace.service → /workspace                    │
│        └─ konductor-mount@kubeconfig.service → /mnt/kube                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 5: CLOUD-INIT CONFIG                                                  │
│ Time: 8-12s                                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑨ cloud-config.service                                                     │
│     ├─ AFTER: cloud-init.service, network-online.target                     │
│     ├─ AFTER: konductor-mount@*.service (all mount instances)               │
│     ├─ Runs cloud_config_modules:                                           │
│     │   ├─ disk_setup (if configured)                                       │
│     │   ├─ mounts (if configured)                                           │
│     │   ├─ set_passwords                                                    │
│     │   ├─ runcmd                                                           │
│     │   └─ ssh                                                              │
│     └─ Output: /dev/ttyS0 (serial console)                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 6: CLOUD-INIT FINAL                                                   │
│ Time: 12-60s (depends on nix builds)                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑩ cloud-final.service                                                      │
│     ├─ AFTER: cloud-config.service, network-online.target                   │
│     ├─ Runs cloud_final_modules:                                            │
│     │   ├─ scripts_vendor                                                   │
│     │   ├─ scripts_per_once                                                 │
│     │   ├─ scripts_per_boot                                                 │
│     │   ├─ scripts_per_instance                                             │
│     │   ├─ scripts_user (runcmd scripts)                                    │
│     │   ├─ ssh_authkey_fingerprints                                         │
│     │   ├─ phone_home (if configured)                                       │
│     │   └─ final_message                                                    │
│     └─ Output: /dev/ttyS0 (serial console)                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 7: VALIDATION GATE                                                    │
│ Time: 60-120s                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑪ konductor.service  ◀━━━━━━━━━━━ THE CRITICAL GATE ━━━━━━━━━━━━━━━━━━━━━  │
│     │                                                                       │
│     ├─ DEPENDENCIES:                                                        │
│     │   ├─ After: cloud-final.service                                       │
│     │   ├─ After: konductor-mount@workspace.service                         │
│     │   ├─ After: konductor-mount@kubeconfig.service                        │
│     │   └─ WantedBy: multi-user.target                                      │
│     │                                                                       │
│     ├─ VALIDATION CHECKS (in order):                                        │
│     │   ├─ [PROVENANCE] git_commit matches build                            │
│     │   ├─ [PROVENANCE] flake_lock_sha256 matches                           │
│     │   ├─ [PROVENANCE] nix_drv reproducible                                │
│     │   ├─ [SECURITY]   SGX EPC sections available                          │
│     │   ├─ [STORAGE]    /workspace group kc2                            │
│     │   ├─ [STORAGE]    /workspace mode 2775                                │
│     │   ├─ [STORAGE]    /workspace writable by kc2, kc2admin, runner        │
│     │   └─ [SERVICES]   Required services healthy                           │
│     │                                                                       │
│     ├─ EXIT CODE LOGIC:                                                     │
│     │   ┌─────────────────────────────────────────────────────────────┐     │
│     │   │ if validation_passed:                                       │     │
│     │   │     exit 0  # SUCCESS - all checks passed                   │     │
│     │   │ elif strict == true:                                        │     │
│     │   │     exit 1  # FAILURE - blocks dependent services           │     │
│     │   │ else:  # strict == false                                    │     │
│     │   │     exit 0  # DEGRADED - warns but allows continuation      │     │
│     │   └─────────────────────────────────────────────────────────────┘     │
│     │                                                                       │
│     └─ OUTPUT: All validation results to /dev/ttyS0                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
     ┌──────────────────────────┐        ┌──────────────────────────┐
     │ konductor.service: OK    │        │ konductor.service: FAIL  │
     │ (exit 0)                 │        │ (exit 1, strict=true)    │
     └──────────────────────────┘        └──────────────────────────┘
                    │                                   │
                    ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 8: APPLICATION SERVICES                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⑫ forgejo-runner.service                                                   │
│     ├─ Requires: konductor.service                                          │
│     ├─ After: konductor.service                                             │
│     ├─ IF konductor.service FAILED (exit 1):                                │
│     │   └─ forgejo-runner will NOT START                                    │
│     │   └─ CI jobs cannot execute                                           │
│     │   └─ This is INTENTIONAL for strict=true                              │
│     └─ IF konductor.service OK (exit 0):                                    │
│         └─ forgejo-runner STARTS                                            │
│         └─ CI jobs can execute                                              │
│                                                                             │
│  ⑬ docker.service (on-demand, started by runcmd)                            │
│  ⑭ libvirtd.service (on-demand, started by runcmd)                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Exit Code Logic

The `konductor.service` exit code is the sole mechanism for controlling downstream service behavior.

### Exit Code Matrix

| Validation | strict | Exit Code | systemd Status | forgejo-runner | Console Output |
|------------|--------|-----------|----------------|----------------|----------------|
| PASS | true | 0 | active | STARTS | `=== VERIFIED (strict=true) ===` |
| PASS | false | 0 | active | STARTS | `=== VERIFIED (strict=false) ===` |
| FAIL | true | 1 | failed | BLOCKED | `=== FAILED (strict=true) ===` |
| FAIL | false | 0 | active | STARTS | `=== DEGRADED (strict=false) ===` |

### Exit Code Flow Diagram

```
                    ┌─────────────────────┐
                    │  Run Validations    │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  All Checks Pass?   │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │ YES                             │ NO
              ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │ Log: VERIFIED   │               │ strict=true?    │
    │ Exit: 0         │               └────────┬────────┘
    └─────────────────┘                        │
                                  ┌────────────┴────────────┐
                                  │ YES                     │ NO
                                  ▼                         ▼
                        ┌─────────────────┐       ┌─────────────────┐
                        │ Log: FAILED     │       │ Log: DEGRADED   │
                        │ Log: BLOCKING   │       │ Log: WARNING    │
                        │ Exit: 1         │       │ Exit: 0         │
                        └─────────────────┘       └─────────────────┘
```

---

## Validation Checks

### Check Categories

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PROVENANCE CHECKS (Software Supply Chain)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  git_commit                                                                 │
│  ├─ Source: /.konductor (baked at build time)                               │
│  ├─ Verify: Commit hash matches expected                                    │
│  └─ Failure: Build provenance cannot be verified                            │
│                                                                             │
│  flake_lock_sha256                                                          │
│  ├─ Source: /.konductor (sha256 of flake.lock at build time)                │
│  ├─ Verify: Hash matches expected                                           │
│  └─ Failure: Dependency integrity cannot be verified                        │
│                                                                             │
│  nix_drv                                                                    │
│  ├─ Source: /.konductor (derivation hash)                                   │
│  ├─ Verify: Derivation is reproducible                                      │
│  └─ Failure: Build reproducibility cannot be verified                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ SECURITY CHECKS (Hardware Root of Trust)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  sgx_epc                                                                    │
│  ├─ Source: /sys/devices/system/node/node*/sgx_epc* or dmesg                │
│  ├─ Verify: SGX EPC sections > 0                                            │
│  ├─ Failure (strict=true): FATAL - no hardware root of trust                │
│  └─ Failure (strict=false): WARNING - software-only attestation             │
│                                                                             │
│  WHY THIS MATTERS:                                                          │
│  ├─ Konductor validates provenance of ALL software in the supply chain      │
│  ├─ Without SGX, attestation relies on software-only verification           │
│  ├─ Software-only attestation CAN BE SPOOFED by compromised hypervisor      │
│  └─ Production CI (merges to main) MUST have hardware root of trust         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ STORAGE CHECKS (Workspace Integrity)                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  workspace_group                                                            │
│  ├─ Source: stat /workspace                                                 │
│  ├─ Expected: group kc2 (GID 1001)                                          │
│  └─ Failure: Workspace group incorrect                                      │
│                                                                             │
│  workspace_mode                                                             │
│  ├─ Source: stat /workspace                                                 │
│  ├─ Expected: 2775 (setgid for group inheritance)                           │
│  └─ Failure: Workspace permissions incorrect                                │
│                                                                             │
│  workspace_writable                                                         │
│  ├─ Test: touch /workspace/.konductor-test as kc2, kc2admin, runner         │
│  └─ Failure: Users cannot write to workspace                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ SERVICE CHECKS (Runtime Dependencies)                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  docker (optional, if enabled)                                              │
│  ├─ Check: systemctl is-active docker                                       │
│  └─ Failure: Docker service not running                                     │
│                                                                             │
│  forgejo-runner registration (optional, if enabled)                         │
│  ├─ Check: Runner config exists and is valid                                │
│  └─ Failure: Runner not registered with Forgejo server                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Console Output Contract

All output goes to `/dev/ttyS0` (serial console) for KubeVirt pod log collection.

### VERIFIED Output (strict=true, all checks pass)

```
═══════════════════════════════════════════════════════════════════════════════
                         KONDUCTOR VALIDATION
═══════════════════════════════════════════════════════════════════════════════
┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
  ✓ git_commit: aedd0e476fddcd44655f5145e74b9a86daa6ef40
  ✓ git_branch: main
  ✓ flake_lock_sha256: c14a6562b72840c9875be855e268be83c22d56b83e66117e75efed5e6e54f87e
  ✓ nix_drv: a3np9kdwmkag7ja2d7mcc4p6za18sam3
└─────────────────────────────────────────────────────────────────────────────┘
┌─ SECURITY ──────────────────────────────────────────────────────────────────┐
  ✓ sgx: 4 EPC sections available (256MB total)
  ✓ hardware root of trust: AVAILABLE
└─────────────────────────────────────────────────────────────────────────────┘
┌─ STORAGE ───────────────────────────────────────────────────────────────────┐
  ✓ /workspace group: kc2
  ✓ /workspace mode: 2775
  ✓ /workspace writable: kc2, kc2admin, runner
└─────────────────────────────────────────────────────────────────────────────┘
┌─ SERVICES ──────────────────────────────────────────────────────────────────┐
  ✓ docker: active
  ✓ forgejo-runner: registered (konductor-dev-0)
└─────────────────────────────────────────────────────────────────────────────┘
═══════════════════════════════════════════════════════════════════════════════
                    ✓ VERIFIED (strict=true)
═══════════════════════════════════════════════════════════════════════════════
```

### FAILED Output (strict=true, validation failed)

```
═══════════════════════════════════════════════════════════════════════════════
                         KONDUCTOR VALIDATION
═══════════════════════════════════════════════════════════════════════════════
┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
  ✓ git_commit: aedd0e476fddcd44655f5145e74b9a86daa6ef40
  ✓ flake_lock_sha256: c14a6562b72840c9875be855e268be83c22d56b83e66117e75efed5e6e54f87e
  ✓ nix_drv: a3np9kdwmkag7ja2d7mcc4p6za18sam3
└─────────────────────────────────────────────────────────────────────────────┘
┌─ SECURITY ──────────────────────────────────────────────────────────────────┐
  ✗ sgx: NO EPC SECTIONS AVAILABLE
  ✗ hardware root of trust: UNAVAILABLE
└─────────────────────────────────────────────────────────────────────────────┘
┌─ STORAGE ───────────────────────────────────────────────────────────────────┐
  ✗ /workspace group: users (expected kc2)
  ✗ /workspace mode: 775 (expected 2775)
  ✓ /workspace writable: kc2, kc2admin, runner
└─────────────────────────────────────────────────────────────────────────────┘
═══════════════════════════════════════════════════════════════════════════════
  FATAL: strict=true requires ALL validations to pass

  FAILURES:
    - sgx: Hardware root of trust unavailable
    - /workspace: Ownership/permissions incorrect

  IMPACT:
    - forgejo-runner will NOT start
    - CI jobs cannot execute
    - This VM cannot be used for production CI

  RESOLUTION:
    - Ensure host has SGX enabled in BIOS
    - Ensure QEMU is configured with SGX passthrough
    - Fix workspace group: chgrp kc2 /workspace && chmod 2775 /workspace
═══════════════════════════════════════════════════════════════════════════════
                    ✗ FAILED (strict=true)
═══════════════════════════════════════════════════════════════════════════════
```

### DEGRADED Output (strict=false, validation failed)

```
═══════════════════════════════════════════════════════════════════════════════
                         KONDUCTOR VALIDATION
═══════════════════════════════════════════════════════════════════════════════
┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐
  ✓ git_commit: aedd0e476fddcd44655f5145e74b9a86daa6ef40
  ✓ flake_lock_sha256: c14a6562b72840c9875be855e268be83c22d56b83e66117e75efed5e6e54f87e
  ✓ nix_drv: a3np9kdwmkag7ja2d7mcc4p6za18sam3
└─────────────────────────────────────────────────────────────────────────────┘
┌─ SECURITY ──────────────────────────────────────────────────────────────────┐
  ⚠ sgx: NO EPC SECTIONS AVAILABLE
  ⚠ hardware root of trust: UNAVAILABLE (software-only attestation)
└─────────────────────────────────────────────────────────────────────────────┘
┌─ STORAGE ───────────────────────────────────────────────────────────────────┐
  ✓ /workspace group: kc2
  ✓ /workspace mode: 2775
  ✓ /workspace writable: kc2, kc2admin, runner
└─────────────────────────────────────────────────────────────────────────────┘
═══════════════════════════════════════════════════════════════════════════════
  WARNING: Running in DEGRADED MODE (strict=false)

  ISSUES:
    - sgx: Software-only attestation (no hardware root of trust)

  IMPACT:
    - forgejo-runner WILL start (strict=false allows degraded operation)
    - CI jobs CAN execute
    - Results should NOT be used for merges to main
    - This configuration is NOT suitable for production

  FOR PRODUCTION:
    - Set strict=true in /.konductor
    - Ensure SGX hardware is available and configured
═══════════════════════════════════════════════════════════════════════════════
                    ⚠ DEGRADED (strict=false)
═══════════════════════════════════════════════════════════════════════════════
```

---

## Environment Mapping

| Environment | Git Branch | strict | On Validation Fail |
|-------------|------------|--------|-------------------|
| Production CI | main | `true` | BLOCK - exit 1, no CI |
| Staging CI | staging | `true` | BLOCK - exit 1, no CI |
| PR CI | feature/*, fix/* | `false` | WARN - exit 0, CI runs |
| Local Development | any | `false` | WARN - exit 0, full workflow |

### Setting strict Mode

The `strict` flag is read from `/.konductor` (TOML format):

```toml
[konductor]
strict = true   # Production: block on validation failure
# strict = false  # Development: warn but continue
```

This file is baked into the QCOW2 image at build time. Different images are built for different environments:
- `konductor-prod.qcow2` - strict=true
- `konductor-dev.qcow2` - strict=false

---

## Service Dependency Summary

```nix
# Systemd service dependencies (NixOS configuration)

systemd.services = {
  # ─────────────────────────────────────────────────────────────────────────
  # Mount services - run early, before cloud-config
  # ─────────────────────────────────────────────────────────────────────────
  "konductor-mount@" = {
    after = [ "local-fs.target" ];
    before = [ "cloud-config.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  # ─────────────────────────────────────────────────────────────────────────
  # Validation gate - runs after cloud-init completes
  # ─────────────────────────────────────────────────────────────────────────
  konductor = {
    after = [
      "cloud-final.service"
      "konductor-mount@workspace.service"
      "konductor-mount@kubeconfig.service"
    ];
    wants = [
      "cloud-final.service"
    ];
    wantedBy = [ "multi-user.target" ];
    # Exit code determines if dependent services start
    # strict=true + fail → exit 1 → dependents blocked
    # strict=false + fail → exit 0 → dependents start
  };

  # ─────────────────────────────────────────────────────────────────────────
  # Application services - gated by konductor.service
  # ─────────────────────────────────────────────────────────────────────────
  forgejo-runner = {
    requires = [ "konductor.service" ];  # Won't start if konductor failed
    after = [ "konductor.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  # Don't auto-start these (cloud-init runcmd starts them if needed)
  docker.wantedBy = lib.mkForce [ ];
  libvirtd.wantedBy = lib.mkForce [ ];
  "libvirt-guests".wantedBy = lib.mkForce [ ];
};
```

---

## References

- [Cloud-init NixOS Integration Guide](./developer_guide/qcow2/CLOUD_INIT_NIXOS_INTEGRATION.md)
- [NixOS cloud-init module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/system/cloud-init.nix)
- [Intel SGX Documentation](https://www.intel.com/content/www/us/en/developer/tools/software-guard-extensions/overview.html)
