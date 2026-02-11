"""Konductor PKI cryptographic operations.

P-384 (secp384r1) for CA certificates -- 192-bit security for long-lived keys.
P-256 (secp256r1) for leaf certificates -- max compatibility, faster operations.

All certificate operations use the Python cryptography library, not OpenSSL CLI.
"""
