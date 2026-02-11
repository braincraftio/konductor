"""Root CA certificate builder.

Generates a self-signed root CA certificate with:
  - EC P-384 key (from keys.py)
  - basicConstraints: critical, CA:TRUE, pathLenConstraint=None
  - keyUsage: critical, digitalSignature, keyCertSign, cRLSign
  - subjectKeyIdentifier: hash of public key
  - Custom OID extensions: build provenance from /.konductor
  - nsComment: human-readable provenance for browser cert viewer

The CA certificate is the root of the VM's local trust chain.
"""

from __future__ import annotations

import datetime

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePrivateKey
from cryptography.x509.oid import NameOID

from pki import config
from pki.crypto.extensions import build_provenance_extensions, der_ia5string
from pki.identity import CertificateIdentity, TrustTier


def build_ca_certificate(
    ca_key: EllipticCurvePrivateKey,
    identity: CertificateIdentity,
    trust_tier: TrustTier,
    validity_days: int = 3650,
) -> x509.Certificate:
    """Build a self-signed root CA certificate.

    Args:
        ca_key: P-384 private key for the CA.
        identity: Certificate identity from fingerprint.
        trust_tier: Trust tier for provenance metadata.
        validity_days: CA certificate validity (default 10 years).

    Returns:
        Self-signed X.509 CA certificate.
    """
    now = datetime.datetime.now(datetime.timezone.utc)

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, identity.organization),
        x509.NameAttribute(
            NameOID.ORGANIZATIONAL_UNIT_NAME, identity.organizational_unit
        ),
        x509.NameAttribute(NameOID.COMMON_NAME, identity.ca_common_name),
        x509.NameAttribute(NameOID.SERIAL_NUMBER, identity.serial_hex),
    ])

    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(ca_key.public_key())
        .serial_number(identity.deterministic_serial("ca"))
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=validity_days))
        # CA:TRUE with no path length constraint (allows recursive chains)
        .add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True,
        )
        # Key usage for CA operations
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_cert_sign=True,
                crl_sign=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        # Subject Key Identifier
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()),
            critical=False,
        )
    )

    # nsComment -- visible in every browser's certificate viewer
    ns_comment = identity.ns_comment("Root CA", trust_tier)
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

    # Sign with SHA-384 (matches P-384 key strength)
    return builder.sign(ca_key, hashes.SHA384())
