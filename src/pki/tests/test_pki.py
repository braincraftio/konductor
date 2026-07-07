"""Konductor PKI -- end-to-end certificate issuance tests.

Exercises the real crypto pipeline with real keys.  No mocks of
cryptography internals -- if these pass, the systemd services will
produce valid, verifiable certificates.

Run:
    nix-shell -p 'python3.withPackages (ps: [ps.cryptography ps.pytest])' \
      --run 'python3 -m pytest src/pki/tests/ -v'
"""

from __future__ import annotations

import datetime
import textwrap

import pytest
from cryptography import x509
from cryptography.hazmat.primitives.asymmetric.ec import (
    ECDSA,
    SECP256R1,
    SECP384R1,
    EllipticCurvePublicKey,
)
from cryptography.hazmat.primitives.hashes import SHA256, SHA384
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

from pki import config
from pki.cli import cmd_status
from pki.crypto.bundle import build_bundle
from pki.crypto.ca import build_ca_certificate
from pki.crypto.extensions import (
    decode_provenance_value,
    der_ia5string,
    _der_utf8string,
)
from pki.crypto.keys import (
    generate_ca_key,
    generate_leaf_key,
    load_private_key,
    write_private_key,
)
from pki.crypto.leaf import build_leaf_certificate
from pki.fingerprint import Fingerprint, FingerprintError, OSRelease
from pki.identity import CertificateIdentity, TrustTier


# =====================================================================
# Fixtures
# =====================================================================

SAMPLE_FINGERPRINT = Fingerprint(
    git_commit="abcdef1234567890abcdef1234567890abcdef12",
    git_branch="main",
    git_remote="https://git.braincraft.io/braincraft/k9",
    nix_drv="abc123xyz456",
    nix_hash="sha256-AAAA",
    build_date="2025-01-15T10:30:00Z",
    build_host="builder",
    build_user="nix",
)

SAMPLE_OSRELEASE = OSRelease(
    version_id="25.11",
    version_codename="xantusia",
    name="NixOS",
    hostname="test-vm",
)

DOMAIN = "test.konductor.arpa"


@pytest.fixture
def identity() -> CertificateIdentity:
    return CertificateIdentity(
        domain=DOMAIN,
        organization="TestOrg",
        organizational_unit="TestOU",
        fingerprint=SAMPLE_FINGERPRINT,
        osrelease=SAMPLE_OSRELEASE,
    )


@pytest.fixture
def empty_identity() -> CertificateIdentity:
    """Identity with no fingerprint (simulates missing /.konductor)."""
    return CertificateIdentity(
        domain=DOMAIN,
        organization="TestOrg",
        organizational_unit="TestOU",
        fingerprint=Fingerprint(),
        osrelease=OSRelease(),
    )


@pytest.fixture
def ca_key():
    return generate_ca_key()


@pytest.fixture
def leaf_key():
    return generate_leaf_key()


@pytest.fixture
def ca_cert(ca_key, identity):
    return build_ca_certificate(ca_key, identity, TrustTier.SELF_SIGNED)


@pytest.fixture
def leaf_cert(leaf_key, ca_key, ca_cert, identity):
    return build_leaf_certificate(
        leaf_key, ca_key, ca_cert, identity, TrustTier.SELF_SIGNED
    )


# =====================================================================
# Key generation
# =====================================================================


class TestKeyGeneration:
    def test_ca_key_is_p384(self, ca_key):
        assert isinstance(ca_key.curve, SECP384R1)

    def test_leaf_key_is_p256(self, leaf_key):
        assert isinstance(leaf_key.curve, SECP256R1)

    def test_serialize_roundtrip(self, ca_key, tmp_path):
        key_path = tmp_path / "test.key"
        write_private_key(key_path, ca_key, 0o600)
        loaded = load_private_key(key_path)
        # Same key material -- public points match
        assert (
            ca_key.public_key().public_numbers()
            == loaded.public_key().public_numbers()
        )

    def test_key_file_permissions(self, ca_key, tmp_path):
        key_path = tmp_path / "test.key"
        write_private_key(key_path, ca_key, 0o600)
        import os, stat
        mode = stat.S_IMODE(os.stat(key_path).st_mode)
        assert mode == 0o600


# =====================================================================
# CA certificate
# =====================================================================


class TestCACertificate:
    def test_is_self_signed(self, ca_cert):
        assert ca_cert.subject == ca_cert.issuer

    def test_is_ca(self, ca_cert):
        bc = ca_cert.extensions.get_extension_for_class(x509.BasicConstraints)
        assert bc.critical is True
        assert bc.value.ca is True
        assert bc.value.path_length is None

    def test_key_usage(self, ca_cert):
        ku = ca_cert.extensions.get_extension_for_class(x509.KeyUsage)
        assert ku.critical is True
        assert ku.value.digital_signature is True
        assert ku.value.key_cert_sign is True
        assert ku.value.crl_sign is True
        assert ku.value.key_encipherment is False

    def test_subject_dn(self, ca_cert, identity):
        cn = ca_cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
        assert cn == f"{DOMAIN} Root CA"
        org = ca_cert.subject.get_attributes_for_oid(NameOID.ORGANIZATION_NAME)[0].value
        assert org == "TestOrg"

    def test_serial_number_in_dn(self, ca_cert, identity):
        sn = ca_cert.subject.get_attributes_for_oid(NameOID.SERIAL_NUMBER)[0].value
        assert sn == identity.serial_hex
        assert len(sn) == 16

    def test_validity(self, ca_cert):
        now = datetime.datetime.now(datetime.timezone.utc)
        assert ca_cert.not_valid_before_utc <= now
        assert ca_cert.not_valid_after_utc > now
        delta = ca_cert.not_valid_after_utc - ca_cert.not_valid_before_utc
        assert delta.days >= 3649  # ~10 years

    def test_custom_validity(self, ca_key, identity):
        cert = build_ca_certificate(ca_key, identity, TrustTier.SELF_SIGNED, validity_days=30)
        delta = cert.not_valid_after_utc - cert.not_valid_before_utc
        assert 29 <= delta.days <= 30

    def test_signature_verifies(self, ca_key, ca_cert):
        """CA cert signature is verifiable with its own public key."""
        pub = ca_key.public_key()
        assert isinstance(pub, EllipticCurvePublicKey)
        # This raises if invalid
        pub.verify(
            ca_cert.signature,
            ca_cert.tbs_certificate_bytes,
            ECDSA(SHA384()),
        )

    def test_has_ski(self, ca_cert):
        ski = ca_cert.extensions.get_extension_for_class(
            x509.SubjectKeyIdentifier
        )
        assert ski is not None
        assert len(ski.value.digest) == 20  # SHA-1 hash

    def test_has_ns_comment(self, ca_cert):
        ns_ext = None
        for ext in ca_cert.extensions:
            if ext.oid.dotted_string == config.NS_COMMENT_OID:
                ns_ext = ext
                break
        assert ns_ext is not None

    def test_pem_roundtrip(self, ca_cert):
        pem = ca_cert.public_bytes(Encoding.PEM)
        reloaded = x509.load_pem_x509_certificate(pem)
        assert reloaded.subject == ca_cert.subject
        assert reloaded.serial_number == ca_cert.serial_number


# =====================================================================
# Leaf (wildcard) certificate
# =====================================================================


class TestLeafCertificate:
    def test_not_ca(self, leaf_cert):
        bc = leaf_cert.extensions.get_extension_for_class(x509.BasicConstraints)
        assert bc.critical is True
        assert bc.value.ca is False

    def test_issuer_matches_ca_subject(self, leaf_cert, ca_cert):
        assert leaf_cert.issuer == ca_cert.subject

    def test_key_usage(self, leaf_cert):
        ku = leaf_cert.extensions.get_extension_for_class(x509.KeyUsage)
        assert ku.critical is True
        assert ku.value.digital_signature is True
        assert ku.value.key_encipherment is True
        assert ku.value.key_cert_sign is False

    def test_extended_key_usage(self, leaf_cert):
        eku = leaf_cert.extensions.get_extension_for_class(x509.ExtendedKeyUsage)
        oids = list(eku.value)
        assert ExtendedKeyUsageOID.SERVER_AUTH in oids
        assert ExtendedKeyUsageOID.CLIENT_AUTH in oids

    def test_san_dns_names(self, leaf_cert):
        san = leaf_cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        )
        dns_names = san.value.get_values_for_type(x509.DNSName)
        assert f"*.{DOMAIN}" in dns_names
        assert DOMAIN in dns_names
        assert f"*.docker.{DOMAIN}" in dns_names
        assert f"docker.{DOMAIN}" in dns_names

    def test_san_uri_names(self, leaf_cert):
        san = leaf_cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        )
        uris = san.value.get_values_for_type(x509.UniformResourceIdentifier)
        assert SAMPLE_FINGERPRINT.git_remote in uris

    def test_has_aki(self, leaf_cert):
        aki = leaf_cert.extensions.get_extension_for_class(
            x509.AuthorityKeyIdentifier
        )
        assert aki.value.key_identifier is not None

    def test_aki_matches_ca_ski(self, leaf_cert, ca_cert):
        aki = leaf_cert.extensions.get_extension_for_class(
            x509.AuthorityKeyIdentifier
        )
        ski = ca_cert.extensions.get_extension_for_class(
            x509.SubjectKeyIdentifier
        )
        assert aki.value.key_identifier == ski.value.digest

    def test_signature_verifies_with_ca_key(self, ca_key, leaf_cert):
        """Leaf cert signature is verifiable with the CA public key."""
        ca_key.public_key().verify(
            leaf_cert.signature,
            leaf_cert.tbs_certificate_bytes,
            ECDSA(SHA384()),  # P-384 CA signs with SHA-384
        )

    def test_custom_validity(self, leaf_key, ca_key, ca_cert, identity):
        cert = build_leaf_certificate(
            leaf_key, ca_key, ca_cert, identity, TrustTier.SELF_SIGNED,
            validity_days=7,
        )
        delta = cert.not_valid_after_utc - cert.not_valid_before_utc
        assert 6 <= delta.days <= 7

    def test_different_serial_from_ca(self, leaf_cert, ca_cert):
        assert leaf_cert.serial_number != ca_cert.serial_number


# =====================================================================
# Hypervisor-signed (vertical PKI) flow
# =====================================================================


class TestHypervisorFlow:
    """Simulates the hypervisor trust tier: external CA signs the wildcard."""

    def test_hypervisor_signs_leaf(self, identity):
        hyp_ca_key = generate_ca_key()
        hyp_ca_cert = build_ca_certificate(
            hyp_ca_key, identity, TrustTier.HYPERVISOR
        )

        leaf_key = generate_leaf_key()
        leaf_cert = build_leaf_certificate(
            leaf_key, hyp_ca_key, hyp_ca_cert, identity, TrustTier.HYPERVISOR,
        )

        # Verify chain: leaf signed by hypervisor CA
        assert leaf_cert.issuer == hyp_ca_cert.subject
        hyp_ca_key.public_key().verify(
            leaf_cert.signature,
            leaf_cert.tbs_certificate_bytes,
            ECDSA(SHA384()),
        )

    def test_p256_ca_signs_with_sha256(self, identity):
        """If hypervisor provides a P-256 CA, leaf uses SHA-256."""
        p256_ca_key = generate_leaf_key()  # P-256
        p256_ca_cert = build_ca_certificate(
            p256_ca_key, identity, TrustTier.HYPERVISOR,
        )

        leaf_key = generate_leaf_key()
        leaf_cert = build_leaf_certificate(
            leaf_key, p256_ca_key, p256_ca_cert, identity, TrustTier.HYPERVISOR,
        )

        # Should verify with SHA-256 (matching P-256 curve)
        p256_ca_key.public_key().verify(
            leaf_cert.signature,
            leaf_cert.tbs_certificate_bytes,
            ECDSA(SHA256()),
        )


# =====================================================================
# Orphaned certificates (missing /.konductor)
# =====================================================================


class TestNoFingerprint:
    """Certs must generate cleanly even without /.konductor (orphaned mode)."""

    def test_generate_with_empty_fingerprint(self, empty_identity):
        ca_key = generate_ca_key()
        ca_cert = build_ca_certificate(
            ca_key, empty_identity, TrustTier.SELF_SIGNED
        )
        leaf_key = generate_leaf_key()
        leaf_cert = build_leaf_certificate(
            leaf_key, ca_key, ca_cert, empty_identity, TrustTier.SELF_SIGNED,
        )

        # Basic sanity
        assert ca_cert.subject == ca_cert.issuer
        assert leaf_cert.issuer == ca_cert.subject

        # Serial should use fallback (domain hash), not crash
        assert ca_cert.serial_number > 0
        assert leaf_cert.serial_number > 0

        # Signature still verifiable
        ca_key.public_key().verify(
            leaf_cert.signature,
            leaf_cert.tbs_certificate_bytes,
            ECDSA(SHA384()),
        )

    def test_no_uri_sans_without_fingerprint(self, empty_identity):
        ca_key = generate_ca_key()
        ca_cert = build_ca_certificate(
            ca_key, empty_identity, TrustTier.SELF_SIGNED
        )
        leaf_key = generate_leaf_key()
        leaf_cert = build_leaf_certificate(
            leaf_key, ca_key, ca_cert, empty_identity, TrustTier.SELF_SIGNED,
        )

        san = leaf_cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        )
        uris = san.value.get_values_for_type(x509.UniformResourceIdentifier)
        assert uris == []  # No git_remote => no URI SANs

    def test_serial_hex_zeros_without_commit(self, empty_identity):
        assert empty_identity.serial_hex == "0" * 16


# =====================================================================
# Provenance extensions roundtrip
# =====================================================================


class TestProvenance:
    def test_der_utf8string_roundtrip(self):
        for val in ["hello", "a" * 200, "git:abc1234"]:
            encoded = _der_utf8string(val)
            decoded = decode_provenance_value(encoded)
            assert decoded == val

    def test_der_ia5string_encoding(self):
        encoded = der_ia5string("test comment")
        assert encoded[0] == 0x16  # IA5String tag
        assert encoded[2:] == b"test comment"

    def test_provenance_in_cert(self, ca_cert):
        found_oids = set()
        for ext in ca_cert.extensions:
            if ext.oid.dotted_string in config.OID_NAMES:
                found_oids.add(ext.oid.dotted_string)

        # Must have trust tier at minimum
        assert config.OID_TRUST_TIER in found_oids
        # With sample fingerprint, git_commit should be present
        assert config.OID_GIT_COMMIT in found_oids

    def test_provenance_values_decodable(self, ca_cert):
        for ext in ca_cert.extensions:
            name = config.OID_NAMES.get(ext.oid.dotted_string)
            if name:
                val = decode_provenance_value(ext.value.value)
                assert isinstance(val, str)
                assert len(val) > 0

    def test_trust_tier_value(self, ca_cert):
        for ext in ca_cert.extensions:
            if ext.oid.dotted_string == config.OID_TRUST_TIER:
                val = decode_provenance_value(ext.value.value)
                assert val == "self-signed"
                return
        pytest.fail("trust tier OID not found")

    def test_git_commit_value(self, ca_cert):
        for ext in ca_cert.extensions:
            if ext.oid.dotted_string == config.OID_GIT_COMMIT:
                val = decode_provenance_value(ext.value.value)
                assert val == SAMPLE_FINGERPRINT.git_commit
                return
        pytest.fail("git commit OID not found")


# =====================================================================
# CA bundle
# =====================================================================


class TestBundle:
    def test_bundle_aggregates_certs(self, ca_key, ca_cert, tmp_path):
        # Write VM CA
        vm_ca = tmp_path / "vm" / "ca.crt"
        vm_ca.parent.mkdir(parents=True)
        vm_ca.write_bytes(ca_cert.public_bytes(Encoding.PEM))

        # Write a fake system CA
        sys_ca = tmp_path / "system-ca.crt"
        sys_ca.write_bytes(ca_cert.public_bytes(Encoding.PEM))

        # No hypervisor CA
        hyp_ca = tmp_path / "nonexistent-hyp.crt"

        bundle_path = tmp_path / "bundle" / "ca-bundle.crt"

        count = build_bundle(
            output=bundle_path,
            system_ca=sys_ca,
            vm_ca=vm_ca,
            hypervisor_ca=hyp_ca,
        )

        assert bundle_path.exists()
        content = bundle_path.read_text()
        assert count == 2  # system + vm
        assert content.count("BEGIN CERTIFICATE") == 2

    def test_bundle_empty_sources(self, tmp_path):
        bundle_path = tmp_path / "bundle" / "ca-bundle.crt"
        count = build_bundle(
            output=bundle_path,
            system_ca=tmp_path / "nope1",
            vm_ca=tmp_path / "nope2",
            hypervisor_ca=tmp_path / "nope3",
        )
        assert count == 0
        assert bundle_path.exists()

    def test_bundle_all_three_sources(self, ca_key, ca_cert, tmp_path):
        pem = ca_cert.public_bytes(Encoding.PEM)
        for name in ["sys.crt", "vm.crt", "hyp.crt"]:
            (tmp_path / name).write_bytes(pem)

        bundle_path = tmp_path / "bundle" / "out.crt"
        count = build_bundle(
            output=bundle_path,
            system_ca=tmp_path / "sys.crt",
            vm_ca=tmp_path / "vm.crt",
            hypervisor_ca=tmp_path / "hyp.crt",
        )
        assert count == 3


# =====================================================================
# Fingerprint parsing
# =====================================================================


class TestFingerprint:
    def test_load_missing_file(self, tmp_path):
        """Missing /.konductor returns ephemeral fingerprint (pre-provenance)."""
        fp = Fingerprint.load(tmp_path / "nonexistent")
        assert fp.git_commit is None
        assert fp.build_date is None
        assert fp.is_ephemeral is True

    def test_load_toml(self, tmp_path):
        toml_file = tmp_path / ".konductor"
        toml_file.write_text(textwrap.dedent("""\
            [konductor]
            git_commit = "abc123"
            git_branch = "main"
            build_date = "2025-01-15"
        """))
        fp = Fingerprint.load(toml_file)
        assert fp.git_commit == "abc123"
        assert fp.git_branch == "main"
        assert fp.build_date == "2025-01-15"
        assert fp.is_ephemeral is False

    def test_load_corrupt_toml_raises(self, tmp_path):
        """Malformed TOML must raise FingerprintError, never silently degrade."""
        bad_file = tmp_path / ".konductor"
        bad_file.write_text(textwrap.dedent("""\
            [konductor]
            git_commit = "abc123"
            nix_version = "nix (Lix, like Nix) 2.93.0
            System type: x86_64-linux
            Features: gc, signed-caches"
            nix_drv = "abc123xyz456"
        """))
        with pytest.raises(FingerprintError, match="Failed to parse"):
            Fingerprint.load(bad_file)

    def test_strict_parser(self, tmp_path):
        flat_file = tmp_path / ".konductor"
        flat_file.write_text(textwrap.dedent("""\
            git_commit = "deadbeef"
            build_host = "myhost"
        """))
        fp = Fingerprint._parse_strict(flat_file)
        assert fp.git_commit == "deadbeef"
        assert fp.build_host == "myhost"

    def test_validate_matching(self):
        """Identical provenance passes validation."""
        baked = Fingerprint(git_commit="abc123", flake_lock_sha256="def456")
        discovered = Fingerprint(git_commit="abc123", flake_lock_sha256="def456")
        assert baked.validate_against(discovered) == []

    def test_validate_mismatch(self):
        """Mismatched git_commit fails validation."""
        baked = Fingerprint(git_commit="abc123")
        discovered = Fingerprint(git_commit="xyz789")
        errors = baked.validate_against(discovered)
        assert len(errors) == 1
        assert "git_commit mismatch" in errors[0]

    def test_validate_flake_lock_mismatch(self):
        """Mismatched flake_lock_sha256 fails validation."""
        baked = Fingerprint(git_commit="abc123", flake_lock_sha256="aaa")
        discovered = Fingerprint(git_commit="abc123", flake_lock_sha256="bbb")
        errors = baked.validate_against(discovered)
        assert len(errors) == 1
        assert "flake_lock_sha256 mismatch" in errors[0]


# =====================================================================
# Identity
# =====================================================================


class TestIdentity:
    def test_deterministic_serial_stable(self, identity):
        s1 = identity.deterministic_serial("ca")
        s2 = identity.deterministic_serial("ca")
        assert s1 == s2

    def test_deterministic_serial_differs_by_context(self, identity):
        s_ca = identity.deterministic_serial("ca")
        s_leaf = identity.deterministic_serial("leaf")
        assert s_ca != s_leaf

    def test_serial_is_positive(self, identity):
        assert identity.deterministic_serial("ca") > 0
        assert identity.deterministic_serial("leaf") > 0

    def test_dns_names(self, identity):
        names = identity.dns_names
        assert len(names) == 4
        assert f"*.{DOMAIN}" in names

    def test_ns_comment_contains_trust_tier(self, identity):
        comment = identity.ns_comment("Root CA", TrustTier.SELF_SIGNED)
        assert "self-signed" in comment
        assert "Root CA" in comment


# =====================================================================
# PKI Status Receipt (end-to-end evidence)
# =====================================================================


class TestPKIStatus:
    """Generate full cert chain and run `pki status` for human-verifiable output.

    This is the receipt. If these print statements don't appear in the
    build log, the pipeline is lying about what it tested.
    """

    def test_status_receipt(self, ca_key, leaf_key, identity, tmp_path, monkeypatch):
        """Generate full chain into tmpdir, run cmd_status, print evidence."""
        import pki.config as cfg

        # Write cert chain to tmpdir
        vm_dir = tmp_path / "vm"
        vm_dir.mkdir()
        bundle_dir = tmp_path / "bundle"
        bundle_dir.mkdir()
        hyp_dir = tmp_path / "hypervisor"
        hyp_dir.mkdir()

        ca_cert = build_ca_certificate(ca_key, identity, TrustTier.SELF_SIGNED)
        leaf_cert = build_leaf_certificate(
            leaf_key, ca_key, ca_cert, identity, TrustTier.SELF_SIGNED
        )

        ca_cert_pem = ca_cert.public_bytes(Encoding.PEM)
        leaf_cert_pem = leaf_cert.public_bytes(Encoding.PEM)

        (vm_dir / "ca.crt").write_bytes(ca_cert_pem)
        (vm_dir / "ca.key").write_bytes(b"PLACEHOLDER")
        (vm_dir / "wildcard.crt").write_bytes(leaf_cert_pem)
        (vm_dir / "wildcard.key").write_bytes(b"PLACEHOLDER")
        bundle_path = bundle_dir / "ca-bundle.crt"
        bundle_path.write_bytes(ca_cert_pem)

        # Patch config paths to tmpdir
        monkeypatch.setattr(cfg, "VM_CA_CERT", vm_dir / "ca.crt")
        monkeypatch.setattr(cfg, "VM_CA_KEY", vm_dir / "ca.key")
        monkeypatch.setattr(cfg, "VM_WILDCARD_CERT", vm_dir / "wildcard.crt")
        monkeypatch.setattr(cfg, "VM_WILDCARD_KEY", vm_dir / "wildcard.key")
        monkeypatch.setattr(cfg, "HYPERVISOR_CA_CERT", hyp_dir / "ca.crt")
        monkeypatch.setattr(cfg, "HYPERVISOR_CA_KEY", hyp_dir / "tls.key")
        monkeypatch.setattr(cfg, "CA_BUNDLE", bundle_path)
        monkeypatch.setattr(cfg, "HYPERVISOR_MOUNT_CA", tmp_path / "mnt-ca.crt")
        monkeypatch.setattr(cfg, "HYPERVISOR_MOUNT_KEY", tmp_path / "mnt-tls.key")
        monkeypatch.setattr(cfg, "FINGERPRINT_PATH", tmp_path / ".konductor")
        monkeypatch.setattr(cfg, "SOURCE_TREE", tmp_path / "src")

        rc = cmd_status([])
        assert rc == 0
