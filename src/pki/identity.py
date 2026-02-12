"""Map build fingerprint to X.509 certificate identity.

Transforms /.konductor provenance and runtime context into X.509
Distinguished Name fields, Subject Alternative Names, serial numbers,
and human-readable provenance strings for certificate extensions.
"""

from __future__ import annotations

import enum
import hashlib
from dataclasses import dataclass

from pki.fingerprint import Fingerprint, OSRelease


class TrustTier(enum.Enum):
    """Certificate trust tier, highest to lowest."""

    HYPERVISOR = "hypervisor"
    CLOUD_INIT = "cloud-init"
    SELF_SIGNED = "self-signed"

    @property
    def display(self) -> str:
        return self.value


@dataclass(frozen=True)
class CertificateIdentity:
    """All identity fields needed to build CA and leaf certificates."""

    domain: str
    organization: str
    organizational_unit: str
    fingerprint: Fingerprint
    osrelease: OSRelease

    # --- Distinguished Name helpers ---

    @property
    def ca_common_name(self) -> str:
        return f"{self.domain} Root CA"

    @property
    def wildcard_common_name(self) -> str:
        return f"*.{self.domain}"

    @property
    def serial_hex(self) -> str:
        """First 16 hex chars of git_commit, or zeros."""
        commit = self.fingerprint.git_commit
        if commit and len(commit) >= 16:
            return commit[:16]
        return "0" * 16

    # --- Serial Number ---

    def deterministic_serial(self, context: str = "") -> int:
        """Derive deterministic serial from git commit hash.

        RFC 5280: serial must be positive, unique per issuer, <= 20 octets.
        We SHA-256 the commit (+ optional context for uniqueness), truncate
        to 20 bytes, and clear the high bit for positivity.

        If no git commit is available, falls back to a hash of the domain
        and context to produce a stable-but-unique serial.
        """
        seed = self.fingerprint.git_commit or self.domain
        material = f"{seed}:{context}".encode("utf-8")
        digest = hashlib.sha256(material).digest()[:20]
        # Clear high bit (serial must be positive per RFC 5280)
        serial_bytes = bytes([digest[0] & 0x7F]) + digest[1:]
        return int.from_bytes(serial_bytes, byteorder="big")

    # --- Subject Alternative Names ---

    @property
    def dns_names(self) -> list[str]:
        """DNS SANs for wildcard certificate."""
        d = self.domain
        return [
            f"*.{d}",
            d,
            f"*.docker.{d}",
            f"docker.{d}",
        ]

    @property
    def uri_names(self) -> list[str]:
        """URI SANs embedding provenance references."""
        uris: list[str] = []
        if self.fingerprint.git_remote:
            uris.append(self.fingerprint.git_remote)
        if self.fingerprint.nix_drv:
            uris.append(f"nix:drv:{self.fingerprint.nix_drv}")
        if self.fingerprint.nix_hash:
            uris.append(f"nix:hash:{self.fingerprint.nix_hash}")
        return uris

    # --- Provenance strings ---

    @property
    def short_commit(self) -> str:
        return self.fingerprint.git_commit or "orphaned"

    @property
    def short_nix_drv(self) -> str:
        return self.fingerprint.nix_drv or "orphaned"

    def ns_comment(self, cert_type: str, trust_tier: TrustTier) -> str:
        """Build nsComment string for browser certificate viewer.

        This is the single most visible field when a user clicks
        'View Certificate' on a self-signed cert warning.
        """
        parts = [
            f"Konductor {cert_type}",
            self.osrelease.display,
            f"git:{self.short_commit}",
            f"nix:{self.short_nix_drv}",
        ]
        if self.fingerprint.build_date:
            date_short = self.fingerprint.build_date.split("T")[0]
            user = self.fingerprint.build_user or "orphaned"
            host = self.fingerprint.build_host or "orphaned"
            parts.append(f"{date_short} {user}@{host}")
        if self.fingerprint.build_hw_vendor and self.fingerprint.build_hw_product:
            parts.append(f"{self.fingerprint.build_hw_vendor} {self.fingerprint.build_hw_product}")
        parts.append(trust_tier.display)
        return " | ".join(parts)

    def provenance_dict(self) -> dict[str, str | None]:
        """All provenance values for custom OID extensions."""
        return {
            "git_commit": self.fingerprint.git_commit,
            "git_remote": self.fingerprint.git_remote,
            "git_branch": self.fingerprint.git_branch,
            "nix_drv": self.fingerprint.nix_drv,
            "nix_hash": self.fingerprint.nix_hash,
            "build_date": self.fingerprint.build_date,
            "build_host": self.fingerprint.build_host,
            "build_user": self.fingerprint.build_user,
            "flake_lock_sha256": self.fingerprint.flake_lock_sha256,
            "nixos_version": self.osrelease.display,
            "build_hw_vendor": self.fingerprint.build_hw_vendor,
            "build_hw_product": self.fingerprint.build_hw_product,
            "build_hw_serial": self.fingerprint.build_hw_serial,
        }
