# Konductor Secure Boot Enablement

Path to enabling UEFI Secure Boot for regulated production environments.

## Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Implementation Path](#implementation-path)
  - [Phase 1: NixOS Lanzaboote Integration](#phase-1-nixos-lanzaboote-integration)
  - [Phase 2: OVMF Secure Boot Build](#phase-2-ovmf-secure-boot-build)
  - [Phase 3: QEMU Local Build](#phase-3-qemu-local-build)
  - [Phase 4: KubeVirt Production](#phase-4-kubevirt-production)
- [Key Management](#key-management)
- [Compliance Considerations](#compliance-considerations)

---

## Overview

Secure Boot establishes a chain of trust from firmware to operating system:

```text
UEFI Firmware (Platform Keys)
    │
    ▼ verifies signature
OVMF EFI Code (Secure Boot enabled)
    │
    ▼ verifies signature
Lanzaboote Stub (signed with sbctl)
    │
    ▼ SHA256 hash validation
Linux Kernel + initrd
    │
    ▼ verified boot
NixOS System
```

**Current State**: Secure Boot disabled (`secureBoot: false`)
**Target State**: Secure Boot enabled with custom or Microsoft-enrolled keys

---

## Architecture

### Component Responsibilities

| Component | Role | Package/Config |
|-----------|------|----------------|
| **lanzaboote** | NixOS Secure Boot bootloader | `nix-community/lanzaboote` |
| **sbctl** | Secure Boot key manager | `pkgs.sbctl` |
| **OVMF** | EFI firmware with Secure Boot | `pkgs.OVMF.override { secureBoot = true; }` |
| **SMM** | System Management Mode (required) | KubeVirt `domain.features.smm.enabled` |

### Boot Chain Verification

```text
Platform Key (PK)
    └── Key Exchange Key (KEK)
            └── Signature Database (db)
                    └── Signed EFI binaries
                            └── lanzaboote stub
                                    └── Verified kernel/initrd
```

---

## Requirements

### NixOS Image Requirements

1. **Lanzaboote** - Replaces systemd-boot with Secure Boot capable stub
2. **sbctl keys** - Must be generated and included in image
3. **Signed kernel** - Kernel and initrd verified via SHA256 hashes
4. **EFI System Partition** - Proper GPT layout (already using qcow-efi)

### Build Host Requirements

1. **OVMF with Secure Boot** - `pkgs.OVMF.override { secureBoot = true; }`
2. **sbctl** - For key generation and signing
3. **Key storage** - Secure location for Secure Boot keys

### KubeVirt Requirements

1. **SMM enabled** - `domain.features.smm.enabled: true`
2. **Secure Boot** - `domain.firmware.bootloader.efi.secureBoot: true`
3. **Secure OVMF ROMs** - KubeVirt provides `OVMF_CODE.secboot.fd`

---

## Implementation Path

### Phase 1: NixOS Lanzaboote Integration

Add lanzaboote to QCOW2 image configuration in `src/qcow2/default.nix`:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Disable systemd-boot (lanzaboote replaces it)
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Enable lanzaboote
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";  # Key location
  };

  # Include sbctl for key management
  environment.systemPackages = [ pkgs.sbctl ];
}
```

**Flake input required**:
```nix
inputs.lanzaboote = {
  url = "github:nix-community/lanzaboote";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Phase 2: OVMF Secure Boot Build

Update `src/packages/konductor.nix` for Secure Boot OVMF:

```nix
{ pkgs }:
let
  # OVMF with Secure Boot support
  ovmfSecure = pkgs.OVMF.override {
    secureBoot = true;
    msVarsTemplate = true;  # Include Microsoft keys for compatibility
  };
in
{
  packages = with pkgs; [
    # ... existing packages ...
    ovmfSecure
  ];

  env = pkgs: {
    # Secure Boot OVMF paths
    OVMF_CODE_SECURE = "${ovmfSecure.fd}/FV/OVMF_CODE.fd";
    OVMF_VARS_SECURE = "${ovmfSecure.fd}/FV/OVMF_VARS.ms.fd";
    # Standard OVMF (non-secure) for compatibility
    OVMF_CODE = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
    OVMF_VARS = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
  };
}
```

### Phase 3: QEMU Local Build

Update BUILD.md QEMU command for Secure Boot testing:

```bash
# Secure Boot enabled QEMU command
qemu-system-x86_64 \
    -machine q35,accel=kvm,smm=on \
    -global driver=cfi.pflash01,property=secure,value=on \
    -m 8192 \
    -cpu host \
    -smp "$(nproc)" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE_SECURE" \
    -drive if=pflash,format=raw,unit=1,file=/tmp/konductor-build-cloud-init/OVMF_VARS.fd \
    -drive file=result/nixos.qcow2,if=virtio,format=qcow2 \
    # ... rest of command
```

**Key differences for Secure Boot**:
- `-machine q35,accel=kvm,smm=on` - Enable SMM
- `-global driver=cfi.pflash01,property=secure,value=on` - Secure flash
- Use `$OVMF_CODE_SECURE` instead of `$OVMF_CODE`

### Phase 4: KubeVirt Production

Update `deploy/kubevirt/base/konductor.yaml`:

```yaml
spec:
  template:
    spec:
      domain:
        features:
          smm:
            enabled: true
        firmware:
          bootloader:
            efi:
              secureBoot: true
```

**Note**: KubeVirt requires SMM when Secure Boot is enabled. The validation webhook will reject VMs with Secure Boot but without SMM.

---

## Key Management

### Option A: Microsoft Keys (Recommended for Compatibility)

Use OVMF with Microsoft keys for broad hardware/firmware compatibility:

```nix
pkgs.OVMF.override {
  secureBoot = true;
  msVarsTemplate = true;
}
```

**Pros**: Works with existing signed bootloaders, broad compatibility
**Cons**: Depends on Microsoft's key infrastructure

### Option B: Custom Keys (Recommended for Air-gapped)

Generate and manage your own Secure Boot keys:

```bash
# Generate keys (in NixOS)
sudo sbctl create-keys

# Keys stored in /var/lib/sbctl:
# - /var/lib/sbctl/keys/PK/PK.key (Platform Key)
# - /var/lib/sbctl/keys/KEK/KEK.key (Key Exchange Key)
# - /var/lib/sbctl/keys/db/db.key (Signature Database Key)

# Sign bootloader
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

# Verify signatures
sudo sbctl verify
```

**Pros**: Full control, no external dependencies
**Cons**: Requires key distribution infrastructure

### Key Enrollment in VMs

For custom keys in KubeVirt VMs:

1. Build custom OVMF_VARS with enrolled keys
2. Include keys in containerDisk image
3. Use cloud-init to enroll keys on first boot

---

## Compliance Considerations

### FedRAMP / NIST 800-53

- **SC-12**: Cryptographic Key Establishment and Management
- **SI-7**: Software, Firmware, and Information Integrity
- Secure Boot satisfies boot integrity verification requirements

### PCI-DSS

- **Requirement 5**: Protect all systems against malware
- Secure Boot prevents unauthorized bootloader modifications

### HIPAA

- **164.312(c)(1)**: Mechanism to authenticate electronic PHI
- Chain of trust from firmware to OS

### Implementation Checklist

- [ ] Generate Secure Boot keys with documented key ceremony
- [ ] Store keys in HSM or secure key management system
- [ ] Document key rotation procedures
- [ ] Enable audit logging for key usage
- [ ] Test boot failure scenarios (unsigned binaries rejected)
- [ ] Document recovery procedures for key compromise

---

## Testing Secure Boot

### Verify Secure Boot Status (in VM)

```bash
# Check if Secure Boot is enabled
bootctl status | grep "Secure Boot"

# Should show: "Secure Boot: enabled (user)" for custom keys
# Or: "Secure Boot: enabled" for Microsoft keys

# Verify lanzaboote signing
sudo sbctl verify
```

### Test Unsigned Binary Rejection

```bash
# Attempt to boot unsigned kernel (should fail)
# This validates Secure Boot is enforcing policy
```

---

## Future Work

1. **Automated key generation** - Cloud-init based key generation
2. **Key rotation** - Automated key rotation with minimal downtime
3. **TPM integration** - Measured boot with TPM attestation
4. **Remote attestation** - Verify VM boot integrity remotely
