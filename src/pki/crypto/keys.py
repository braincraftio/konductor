"""Key generation and serialization.

CA keys use EC P-384 (secp384r1) -- 192-bit security, suitable for
long-lived root CA keys (Microsoft recommends P-384+ for >15yr CAs).

Leaf keys use EC P-256 (secp256r1) -- maximum compatibility with TLS
clients, faster handshakes, sufficient for shorter-lived leaf certs.
"""

from __future__ import annotations

from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.ec import (
    EllipticCurvePrivateKey,
)

from pki import config
from pki.utils import atomic_write


def generate_ca_key() -> EllipticCurvePrivateKey:
    """Generate P-384 private key for CA certificate."""
    return ec.generate_private_key(ec.SECP384R1())


def generate_leaf_key() -> EllipticCurvePrivateKey:
    """Generate P-256 private key for leaf certificate."""
    return ec.generate_private_key(ec.SECP256R1())


def serialize_private_key(key: EllipticCurvePrivateKey) -> bytes:
    """Serialize private key to PEM format (unencrypted)."""
    return key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def write_private_key(
    path: Path,
    key: EllipticCurvePrivateKey,
    mode: int = config.MODE_PRIVATE_KEY,
) -> None:
    """Write private key to file with specified permissions."""
    atomic_write(path, serialize_private_key(key), mode=mode)


def load_private_key(path: Path) -> EllipticCurvePrivateKey:
    """Load PEM-encoded private key from file."""
    pem_data = path.read_bytes()
    key = serialization.load_pem_private_key(pem_data, password=None)
    if not isinstance(key, EllipticCurvePrivateKey):
        raise TypeError(
            f"Expected EC private key, got {type(key).__name__} from {path}"
        )
    return key
