"""Konductor PKI Configuration -- Single Source of Truth.

All filesystem paths, OID definitions, and defaults live here.
No other module should hardcode paths or OIDs.
"""

from __future__ import annotations

import uuid
from pathlib import Path


# =====================================================================
# Filesystem Paths (Immutable Contract)
# =====================================================================
# These paths are the API contract between PKI and all consumers.
# Changing these requires updating: pki.nix, qcow2/default.nix,
# ttyd.nix, ghostty-web.nix, Pulumi models, cloud-init templates.

PKI_BASE = Path("/etc/konductor/pki")
PKI_VM_DIR = PKI_BASE / "vm"
PKI_HYPERVISOR_DIR = PKI_BASE / "hypervisor"
PKI_BUNDLE_DIR = PKI_BASE / "bundle"

# VM identity files
VM_CA_CERT = PKI_VM_DIR / "ca.crt"
VM_CA_KEY = PKI_VM_DIR / "ca.key"
VM_WILDCARD_CERT = PKI_VM_DIR / "wildcard.crt"
VM_WILDCARD_KEY = PKI_VM_DIR / "wildcard.key"

# Hypervisor CA (imported from mount or cloud-init)
HYPERVISOR_CA_CERT = PKI_HYPERVISOR_DIR / "ca.crt"
HYPERVISOR_CA_KEY = PKI_HYPERVISOR_DIR / "ca.key"

# CA Bundle -- THE canonical path. No legacy alternatives.
# All consumers (forgejo-runner, profile scripts, etc.) must use this path.
CA_BUNDLE = PKI_BUNDLE_DIR / "ca-bundle.crt"

# System CA certificates (NixOS managed)
SYSTEM_CA = Path("/etc/ssl/certs/ca-certificates.crt")

# Cloud-init injected cluster CA
CLUSTER_CA = Path("/etc/konductor/cluster-ca.crt")

# Build fingerprint
FINGERPRINT_PATH = Path("/.konductor")

# Source tree (rsynced into VM at build time, includes .git)
SOURCE_TREE = Path("/opt/konductor/src")

# OS release
OS_RELEASE_PATH = Path("/etc/os-release")

# Hypervisor mount points (KubeVirt volume via konductor-mount@ template)
# Infrastructure copies cert-manager secret keys using upstream naming: ca.crt, tls.key
HYPERVISOR_MOUNT_CA = Path("/mnt/pki/ca.crt")
HYPERVISOR_MOUNT_KEY = Path("/mnt/pki/tls.key")


# =====================================================================
# OID Namespace
# =====================================================================
# UUID-based OID arc per ITU-T X.660 / RFC 4122.
# Globally unique, no IANA registration required.
#
# UUID v5(DNS, "konductor.arpa") = deterministic, reproducible.
# After optional IANA PEN registration, replace with:
#   1.3.6.1.4.1.{PEN}.1.x  (build provenance)
#   1.3.6.1.4.1.{PEN}.2.x  (trust metadata)
#
# See: RFC 9371 (PEN registration), RFC 4122 (UUID)

_KONDUCTOR_UUID = uuid.uuid5(uuid.NAMESPACE_DNS, "konductor.arpa")
OID_ARC = f"2.25.{_KONDUCTOR_UUID.int}"

# Build provenance extensions (arc .1.x)
OID_GIT_COMMIT = f"{OID_ARC}.1.1"
OID_GIT_REMOTE = f"{OID_ARC}.1.2"
OID_GIT_BRANCH = f"{OID_ARC}.1.3"
OID_NIX_DRV = f"{OID_ARC}.1.4"
OID_NIX_HASH = f"{OID_ARC}.1.5"
OID_BUILD_DATE = f"{OID_ARC}.1.6"
OID_BUILD_HOST = f"{OID_ARC}.1.7"
OID_BUILD_USER = f"{OID_ARC}.1.8"
OID_FLAKE_LOCK_SHA256 = f"{OID_ARC}.1.9"
OID_NIXOS_VERSION = f"{OID_ARC}.1.10"
OID_BUILD_HW_VENDOR = f"{OID_ARC}.1.11"
OID_BUILD_HW_PRODUCT = f"{OID_ARC}.1.12"
OID_BUILD_HW_SERIAL = f"{OID_ARC}.1.13"

# Trust metadata extensions (arc .2.x)
OID_TRUST_TIER = f"{OID_ARC}.2.1"
OID_IMAGE_SHA256 = f"{OID_ARC}.2.2"
OID_PROVENANCE_URI = f"{OID_ARC}.2.3"

# nsComment OID (Netscape legacy, universally displayed in browser cert viewers)
NS_COMMENT_OID = "2.16.840.1.113730.1.13"

# All OIDs with human-readable names (for inspect command)
OID_NAMES: dict[str, str] = {
    OID_GIT_COMMIT: "gitCommit",
    OID_GIT_REMOTE: "gitRemote",
    OID_GIT_BRANCH: "gitBranch",
    OID_NIX_DRV: "nixDrv",
    OID_NIX_HASH: "nixHash",
    OID_BUILD_DATE: "buildDate",
    OID_BUILD_HOST: "buildHost",
    OID_BUILD_USER: "buildUser",
    OID_FLAKE_LOCK_SHA256: "flakeLockSha256",
    OID_NIXOS_VERSION: "nixosVersion",
    OID_BUILD_HW_VENDOR: "buildHwVendor",
    OID_BUILD_HW_PRODUCT: "buildHwProduct",
    OID_BUILD_HW_SERIAL: "buildHwSerial",
    OID_TRUST_TIER: "trustTier",
    OID_IMAGE_SHA256: "imageSha256",
    OID_PROVENANCE_URI: "provenanceUri",
}


# =====================================================================
# Defaults
# =====================================================================

DEFAULT_DOMAIN = "konductor.arpa"
DEFAULT_ORGANIZATION = "Konductor"
DEFAULT_OU = "Infrastructure"
DEFAULT_CA_VALIDITY_DAYS = 3650   # 10 years
DEFAULT_CERT_VALIDITY_DAYS = 365  # 1 year

# File permission modes
MODE_PRIVATE_KEY = 0o600    # CA private key -- root only
MODE_SERVICE_KEY = 0o640    # Wildcard key -- konductor-pki group read
MODE_CERTIFICATE = 0o644    # Certificates -- world-readable
MODE_DIRECTORY = 0o755       # PKI directories
MODE_PRIVATE_DIR = 0o700     # Hypervisor dir -- root only
