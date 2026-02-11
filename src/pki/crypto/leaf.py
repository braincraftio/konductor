"""Wildcard leaf certificate builder.

Generates a wildcard TLS certificate signed by the CA (or hypervisor CA):
  - EC P-256 key (from keys.py)
  - keyUsage: critical, digitalSignature, keyEncipherment
  - extendedKeyUsage: serverAuth, clientAuth
  - subjectAltName: DNS wildcards + provenance URIs
  - subjectKeyIdentifier: hash
  - authorityKeyIdentifier: keyid from signing CA
  - Custom OID extensions: build provenance
  - nsComment: human-readable provenance

Signing uses the CA's key algorithm hash:
  - P-384 CA key -> SHA-384 signature
  - P-256 CA key -> SHA-256 signature
"""

from __future__ import annotations

import datetime

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.ec import (
    EllipticCurvePrivateKey,
    SECP384R1,
)
from cryptography.x509.oid import NameOID

from pki import config
from pki.crypto.extensions import build_provenance_extensions, der_ia5string
from pki.identity import CertificateIdentity, TrustTier


def _signing_hash(
    signing_key: EllipticCurvePrivateKey,
) -> hashes.SHA256 | hashes.SHA384:
    """Select hash algorithm matching the signing key's curve."""
    if isinstance(signing_key.curve, SECP384R1):
        return hashes.SHA384()
    return hashes.SHA256()


def build_leaf_certificate(
    leaf_key: EllipticCurvePrivateKey,
    signing_key: EllipticCurvePrivateKey,
    signing_cert: x509.Certificate,
    identity: CertificateIdentity,
    trust_tier: TrustTier,
    validity_days: int = 365,
) -> x509.Certificate:
    """Build a wildcard leaf certificate signed by the CA.

    Args:
        leaf_key: P-256 private key for the leaf cert.
        signing_key: CA (or hypervisor CA) private key for signing.
        signing_cert: CA certificate (for AKI and issuer DN).
        identity: Certificate identity from fingerprint.
        trust_tier: Trust tier for provenance metadata.
        validity_days: Leaf certificate validity (default 1 year).

    Returns:
        Signed X.509 wildcard certificate.
    """
    now = datetime.datetime.now(datetime.timezone.utc)

    subject = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, identity.organization),
        x509.NameAttribute(
            NameOID.ORGANIZATIONAL_UNIT_NAME, identity.organizational_unit
        ),
        x509.NameAttribute(NameOID.COMMON_NAME, identity.wildcard_common_name),
        x509.NameAttribute(NameOID.SERIAL_NUMBER, identity.serial_hex),
    ])

    # Build SAN list
    san_names: list[x509.GeneralName] = []
    for dns in identity.dns_names:
        san_names.append(x509.DNSName(dns))
    for uri in identity.uri_names:
        san_names.append(x509.UniformResourceIdentifier(uri))

    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(signing_cert.subject)
        .public_key(leaf_key.public_key())
        .serial_number(identity.deterministic_serial("leaf"))
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=validity_days))
        # Not a CA
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        # TLS server and client authentication
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                key_cert_sign=False,
                crl_sign=False,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([
                x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
                x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH,
            ]),
            critical=False,
        )
        # Subject Alternative Names
        .add_extension(
            x509.SubjectAlternativeName(san_names),
            critical=False,
        )
        # Subject Key Identifier
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(leaf_key.public_key()),
            critical=False,
        )
        # Authority Key Identifier (from signing CA)
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(
                signing_key.public_key()
            ),
            critical=False,
        )
    )

    # nsComment
    ns_comment = identity.ns_comment("Wildcard", trust_tier)
    builder = builder.add_extension(
        x509.UnrecognizedExtension(
            oid=x509.ObjectIdentifier(config.NS_COMMENT_OID),
            value=der_ia5string(ns_comment),
        ),
        critical=False,
    )

    # Custom OID provenance extensions
    for ext in build_provenance_extensions(identity, trust_tier):
        builder = builder.add_extension(ext.value, critical=False)

    return builder.sign(signing_key, _signing_hash(signing_key))
