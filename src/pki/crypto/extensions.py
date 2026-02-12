"""Custom X.509v3 extension builders for build provenance.

Encodes provenance values as DER UTF8String in custom OID extensions,
following the pattern established by Sigstore's Fulcio CA (PEN 57264).

All custom extensions are marked non-critical per RFC 5280 -- unknown
critical extensions cause certificate rejection.

DER encoding reference:
  UTF8String tag = 0x0C
  Length: short form (< 128 bytes) or long form (0x81 + 1 byte / 0x82 + 2 bytes)
  Value: UTF-8 encoded bytes
"""

from __future__ import annotations

from cryptography import x509

from pki import config
from pki.identity import CertificateIdentity, TrustTier


def der_ia5string(value: str) -> bytes:
    """Encode string as DER IA5String (tag 0x16) for nsComment."""
    raw = value.encode("ascii", errors="replace")
    length = len(raw)
    if length < 0x80:
        return bytes([0x16, length]) + raw
    elif length < 0x100:
        return bytes([0x16, 0x81, length]) + raw
    else:
        return bytes([0x16, 0x82, (length >> 8) & 0xFF, length & 0xFF]) + raw


def _der_utf8string(value: str) -> bytes:
    """Encode a string as DER UTF8String (tag 0x0C)."""
    raw = value.encode("utf-8")
    length = len(raw)
    if length < 0x80:
        header = bytes([0x0C, length])
    elif length < 0x100:
        header = bytes([0x0C, 0x81, length])
    elif length < 0x10000:
        header = bytes([0x0C, 0x82, (length >> 8) & 0xFF, length & 0xFF])
    else:
        raise ValueError(f"Value too long for DER encoding: {length} bytes")
    return header + raw


def _provenance_extension(
    oid_str: str,
    value: str | None,
) -> x509.Extension[x509.UnrecognizedExtension] | None:
    """Build a single provenance extension, or None if value is absent."""
    if not value:
        return None
    oid = x509.ObjectIdentifier(oid_str)
    return x509.Extension(
        oid=oid,
        critical=False,
        value=x509.UnrecognizedExtension(oid=oid, value=_der_utf8string(value)),
    )


def build_provenance_extensions(
    identity: CertificateIdentity,
    trust_tier: TrustTier,
) -> list[x509.Extension[x509.UnrecognizedExtension]]:
    """Build all custom OID extensions from certificate identity.

    Returns a list of non-critical extensions encoding build provenance.
    Extensions with None values are omitted.
    """
    prov = identity.provenance_dict()

    candidates = [
        (config.OID_GIT_COMMIT, prov.get("git_commit")),
        (config.OID_GIT_REMOTE, prov.get("git_remote")),
        (config.OID_GIT_BRANCH, prov.get("git_branch")),
        (config.OID_NIX_DRV, prov.get("nix_drv")),
        (config.OID_NIX_HASH, prov.get("nix_hash")),
        (config.OID_BUILD_DATE, prov.get("build_date")),
        (config.OID_BUILD_HOST, prov.get("build_host")),
        (config.OID_BUILD_USER, prov.get("build_user")),
        (config.OID_FLAKE_LOCK_SHA256, prov.get("flake_lock_sha256")),
        (config.OID_NIXOS_VERSION, prov.get("nixos_version")),
        (config.OID_BUILD_HW_VENDOR, prov.get("build_hw_vendor")),
        (config.OID_BUILD_HW_PRODUCT, prov.get("build_hw_product")),
        (config.OID_BUILD_HW_SERIAL, prov.get("build_hw_serial")),
        (config.OID_TRUST_TIER, trust_tier.value),
    ]

    if identity.fingerprint.image_sha256:
        candidates.append(
            (config.OID_IMAGE_SHA256, identity.fingerprint.image_sha256)
        )

    if identity.fingerprint.git_remote:
        candidates.append(
            (config.OID_PROVENANCE_URI, identity.fingerprint.git_remote)
        )

    extensions: list[x509.Extension[x509.UnrecognizedExtension]] = []
    for oid_str, value in candidates:
        ext = _provenance_extension(oid_str, value)
        if ext is not None:
            extensions.append(ext)

    return extensions


def decode_provenance_value(der_bytes: bytes) -> str:
    """Decode a DER UTF8String back to a Python string.

    Used by the inspect command to display provenance from certificates.
    """
    if len(der_bytes) < 2:
        return der_bytes.hex()

    tag = der_bytes[0]
    if tag != 0x0C:
        # Not a UTF8String, return hex representation
        return der_bytes.hex()

    # Parse DER length
    length_byte = der_bytes[1]
    if length_byte < 0x80:
        offset = 2
    elif length_byte == 0x81:
        offset = 3
    elif length_byte == 0x82:
        offset = 4
    else:
        return der_bytes.hex()

    try:
        return der_bytes[offset:].decode("utf-8")
    except UnicodeDecodeError:
        return der_bytes[offset:].hex()
