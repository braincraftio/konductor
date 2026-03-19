"""Konductor PKI CLI -- certificate generation, inspection, and bundle management.

Usage:
    python3 -m pki generate   Generate CA + wildcard cert (idempotent)
    python3 -m pki bundle     Build CA trust bundle
    python3 -m pki inspect    Inspect certificate provenance
    python3 -m pki status     Show PKI status summary
    python3 -m pki hypervisor Import hypervisor-provided certificates
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.serialization import Encoding

from pki import config
from pki.crypto.bundle import build_bundle
from pki.crypto.ca import build_ca_certificate
from pki.crypto.extensions import decode_provenance_value
from pki.crypto.keys import (
    generate_ca_key,
    generate_leaf_key,
    load_private_key,
    write_private_key,
)
from pki.crypto.leaf import build_leaf_certificate
from pki.fingerprint import Fingerprint, FingerprintError, OSRelease
from pki.identity import CertificateIdentity, TrustTier
from pki.utils import action, atomic_write, ensure_dir, err, info, ok


def _load_identity(
    domain: str | None = None,
    organization: str | None = None,
    ou: str | None = None,
) -> CertificateIdentity:
    """Load fingerprint + OS release and build certificate identity.

    Raises FingerprintError if /.konductor exists but is corrupt.
    """
    fp = Fingerprint.load()
    osr = OSRelease.load()
    return CertificateIdentity(
        domain=domain or config.DEFAULT_DOMAIN,
        organization=organization or config.DEFAULT_ORGANIZATION,
        organizational_unit=ou or config.DEFAULT_OU,
        fingerprint=fp,
        osrelease=osr,
    )


def _validate_provenance(fp: Fingerprint) -> None:
    """Validate baked provenance against self-discovered source tree.

    When /.konductor exists (non-ephemeral), self-discovers provenance
    from /opt/konductor/src and validates critical fields match.
    Raises FingerprintError on mismatch.
    """
    if fp.is_ephemeral:
        return

    discovered = Fingerprint.discover()
    errors = fp.validate_against(discovered)
    if errors:
        raise FingerprintError(
            "Provenance integrity validation FAILED:\n"
            + "\n".join(f"  ✗ {e}" for e in errors)
            + "\n  Baked /.konductor does not match source tree at "
            + str(config.SOURCE_TREE)
            + "\n  Refusing to generate certificates with mismatched provenance."
        )


# =====================================================================
# generate -- Create CA + wildcard certificate
# =====================================================================


def cmd_generate(args: list[str]) -> int:
    """Generate CA and wildcard certificate with automatic trust tier detection.

    Trust tier selection (automatic):
    1. If hypervisor CA+key available at /mnt/pki/: cross-sign with hypervisor CA
    2. Otherwise: self-sign (with loud warnings)

    Idempotent: skips if /etc/konductor/pki/vm/ca.crt already exists
    unless --force is passed.

    Provenance enforcement:
    - If /.konductor exists but is malformed: FAIL (FingerprintError)
    - If /.konductor exists but mismatches source tree: FAIL
    - If /.konductor does not exist: orphaned certs, loud warning
    """
    force = "--force" in args
    domain = _extract_flag(args, "--domain")
    org = _extract_flag(args, "--org")
    ou = _extract_flag(args, "--ou")
    ca_days = int(_extract_flag(args, "--ca-days") or config.DEFAULT_CA_VALIDITY_DAYS)
    cert_days = int(
        _extract_flag(args, "--cert-days") or config.DEFAULT_CERT_VALIDITY_DAYS
    )

    if config.VM_CA_CERT.exists() and not force:
        ok(f"CA already exists: {config.VM_CA_CERT}")
        info("Use --force to regenerate")
        return 0

    # Load identity -- FingerprintError propagates as fatal exit
    identity = _load_identity(domain, org, ou)

    # Validate baked provenance against source tree
    _validate_provenance(identity.fingerprint)

    # Detect hypervisor CA availability for cross-signing
    hypervisor_ca_available = (
        config.HYPERVISOR_MOUNT_CA.exists() and
        config.HYPERVISOR_MOUNT_KEY.exists()
    )
    hypervisor_ca_cert = None
    hypervisor_ca_key = None

    if hypervisor_ca_available:
        try:
            hypervisor_ca_cert = x509.load_pem_x509_certificate(
                config.HYPERVISOR_MOUNT_CA.read_bytes()
            )
            hypervisor_ca_key = load_private_key(config.HYPERVISOR_MOUNT_KEY)
            trust_tier = TrustTier.HYPERVISOR
        except Exception as exc:
            # Cross-signing failed, fall back to self-signed
            _warn_degraded_pki(
                f"Hypervisor CA loading failed: {exc}",
                "Falling back to SELF-SIGNED certificates",
            )
            hypervisor_ca_available = False
            trust_tier = TrustTier.SELF_SIGNED
    else:
        trust_tier = TrustTier.SELF_SIGNED
        # Warn about missing hypervisor CA
        missing = []
        if not config.HYPERVISOR_MOUNT_CA.exists():
            missing.append(str(config.HYPERVISOR_MOUNT_CA))
        if not config.HYPERVISOR_MOUNT_KEY.exists():
            missing.append(str(config.HYPERVISOR_MOUNT_KEY))
        _warn_degraded_pki(
            f"Hypervisor CA not available: {', '.join(missing)}",
            "Generating SELF-SIGNED certificates (Envoy Gateway will NOT trust these)",
        )

    print(
        "═══════════════════════════════════════════════════════════════"
    )
    if identity.fingerprint.is_ephemeral:
        print("  ⚠ Konductor PKI -- ORPHANED Certificate Generation")
        print(
            "═══════════════════════════════════════════════════════════════"
        )
        print()
        err("/.konductor not found -- generating ORPHANED certificates")
        err("Certs will be marked git:orphaned | nix:orphaned")
        err("These certs have NO provenance chain and CANNOT be audited")
        err("Run the build pipeline to write /.konductor and regenerate")
        print()
    elif trust_tier == TrustTier.HYPERVISOR:
        print("  Konductor PKI -- Hypervisor Cross-Signed Certificate Generation")
        print(
            "═══════════════════════════════════════════════════════════════"
        )
    else:
        print("  ⚠ Konductor PKI -- Self-Signed Certificate Generation (DEGRADED)")
        print(
            "═══════════════════════════════════════════════════════════════"
        )
    info(f"Domain: {identity.domain}")
    info(f"Organization: {identity.organization}")
    info(f"OU: {identity.organizational_unit}")
    info(f"Serial: {identity.serial_hex}")
    info(f"Trust tier: {trust_tier.display}")
    if not identity.fingerprint.is_ephemeral:
        info(f"Git: {identity.fingerprint.git_commit}")
        info(f"Nix: {identity.fingerprint.nix_drv}")
        info(f"Built: {identity.fingerprint.build_date} by {identity.fingerprint.build_user}@{identity.fingerprint.build_host}")
    print()

    # Ensure directories
    ensure_dir(config.PKI_VM_DIR, config.MODE_DIRECTORY)

    if hypervisor_ca_available and hypervisor_ca_cert and hypervisor_ca_key:
        # Cross-sign path: use hypervisor CA to sign VM CA
        action("Using hypervisor CA for cross-signing")

        # Import hypervisor CA to standard location
        ensure_dir(config.PKI_HYPERVISOR_DIR, config.MODE_PRIVATE_DIR)
        atomic_write(
            config.HYPERVISOR_CA_CERT,
            config.HYPERVISOR_MOUNT_CA.read_bytes(),
            config.MODE_CERTIFICATE,
        )
        atomic_write(
            config.HYPERVISOR_CA_KEY,
            config.HYPERVISOR_MOUNT_KEY.read_bytes(),
            config.MODE_PRIVATE_KEY,
        )
        ok(f"Hypervisor CA imported: {config.HYPERVISOR_CA_CERT}")

        # 1. Generate VM CA key
        action("Generating VM CA key (P-384)")
        ca_key = generate_ca_key()
        write_private_key(config.VM_CA_KEY, ca_key, config.MODE_PRIVATE_KEY)
        ok(f"VM CA key: {config.VM_CA_KEY}")

        # 2. Build VM CA cert signed by hypervisor CA (intermediate CA)
        action("Building VM CA certificate (signed by hypervisor)")
        ca_cert = _build_cross_signed_ca(
            ca_key, hypervisor_ca_key, hypervisor_ca_cert,
            identity, trust_tier, validity_days=ca_days
        )
        atomic_write(
            config.VM_CA_CERT,
            ca_cert.public_bytes(Encoding.PEM),
            config.MODE_CERTIFICATE,
        )
        ok(f"VM CA cert (hypervisor-signed): {config.VM_CA_CERT}")

        # Use VM CA to sign wildcard (not hypervisor CA directly)
        signing_key = ca_key
        signing_cert = ca_cert
    else:
        # Self-sign path
        action("Generating CA key (P-384)")
        ca_key = generate_ca_key()
        write_private_key(config.VM_CA_KEY, ca_key, config.MODE_PRIVATE_KEY)
        ok(f"CA key: {config.VM_CA_KEY}")

        action("Building CA certificate (self-signed)")
        ca_cert = build_ca_certificate(
            ca_key, identity, trust_tier, validity_days=ca_days
        )
        atomic_write(
            config.VM_CA_CERT,
            ca_cert.public_bytes(Encoding.PEM),
            config.MODE_CERTIFICATE,
        )
        ok(f"CA cert: {config.VM_CA_CERT}")

        signing_key = ca_key
        signing_cert = ca_cert

    # 3. Wildcard key (P-256)
    action("Generating wildcard key (P-256)")
    leaf_key = generate_leaf_key()
    write_private_key(config.VM_WILDCARD_KEY, leaf_key, config.MODE_SERVICE_KEY)
    ok(f"Wildcard key: {config.VM_WILDCARD_KEY}")

    # 4. Wildcard certificate (signed by VM CA)
    action("Building wildcard certificate")
    leaf_cert = build_leaf_certificate(
        leaf_key, signing_key, signing_cert, identity, trust_tier, validity_days=cert_days
    )
    # Write full chain: leaf + signing CA intermediate
    # Envoy needs the intermediate to verify against root CA in ConfigMap
    chain_pem = leaf_cert.public_bytes(Encoding.PEM) + signing_cert.public_bytes(Encoding.PEM)
    atomic_write(
        config.VM_WILDCARD_CERT,
        chain_pem,
        config.MODE_CERTIFICATE,
    )
    ok(f"Wildcard cert (chain): {config.VM_WILDCARD_CERT}")

    print()
    _print_cert_summary("CA", ca_cert)
    _print_cert_summary("Wildcard", leaf_cert)

    # Final warning if degraded
    if trust_tier == TrustTier.SELF_SIGNED:
        print()
        _warn_degraded_pki(
            "PKI is SELF-SIGNED (degraded mode)",
            "Services will NOT be accessible via Envoy Gateway until hypervisor CA is mounted",
        )

    print()
    ok("PKI generation complete")
    return 0


def _warn_degraded_pki(reason: str, consequence: str) -> None:
    """Emit loud warnings to stdout, stderr, and console for degraded PKI."""
    warning_block = f"""
════════════════════════════════════════════════════════════════════════════════
  ⚠⚠⚠  DEGRADED PKI WARNING  ⚠⚠⚠
════════════════════════════════════════════════════════════════════════════════
  Reason: {reason}
  Impact: {consequence}
════════════════════════════════════════════════════════════════════════════════
"""
    # stdout
    print(warning_block)
    # stderr (for log aggregators)
    print(warning_block, file=sys.stderr)
    # Try to write to console devices for boot-time visibility
    for console in ["/dev/console", "/dev/ttyS0", "/dev/tty0"]:
        try:
            with open(console, "w") as f:
                f.write(warning_block)
        except (OSError, PermissionError):
            pass  # Not available or no permission


def _build_cross_signed_ca(
    ca_key,
    issuer_key,
    issuer_cert: x509.Certificate,
    identity: CertificateIdentity,
    trust_tier: TrustTier,
    validity_days: int = 3650,
) -> x509.Certificate:
    """Build VM CA certificate signed by hypervisor CA (intermediate CA).

    Creates a valid intermediate CA that:
    - Is signed by the hypervisor/platform CA
    - Can sign leaf certificates (wildcard)
    - Includes Authority Key Identifier linking to issuer
    - Has pathLenConstraint=0 (can only sign end-entity certs)
    """
    import datetime
    from cryptography.hazmat.primitives import hashes

    now = datetime.datetime.now(datetime.timezone.utc)

    subject = x509.Name([
        x509.NameAttribute(x509.oid.NameOID.ORGANIZATION_NAME, identity.organization),
        x509.NameAttribute(
            x509.oid.NameOID.ORGANIZATIONAL_UNIT_NAME, identity.organizational_unit
        ),
        x509.NameAttribute(x509.oid.NameOID.COMMON_NAME, identity.ca_common_name),
        x509.NameAttribute(x509.oid.NameOID.SERIAL_NUMBER, identity.serial_hex),
    ])

    # Issuer is the hypervisor CA's subject
    issuer = issuer_cert.subject

    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(ca_key.public_key())
        .serial_number(identity.deterministic_serial("ca"))
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=validity_days))
        # CA:TRUE with pathLenConstraint=0 (can only sign leaf certs)
        .add_extension(
            x509.BasicConstraints(ca=True, path_length=0),
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
        # Authority Key Identifier (links to issuer)
        # Use from_issuer_subject_key_identifier to copy the SKI directly
        # from the issuer cert. from_issuer_public_key recomputes it via
        # SHA-1, which may differ from how cert-manager computed the SKI.
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_subject_key_identifier(
                issuer_cert.extensions.get_extension_for_class(
                    x509.SubjectKeyIdentifier
                ).value
            ),
            critical=False,
        )
    )

    # nsComment
    from pki.crypto.extensions import build_provenance_extensions, der_ia5string
    ns_comment = identity.ns_comment("Intermediate CA", trust_tier)
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

    # Sign with issuer's key (hypervisor CA)
    return builder.sign(issuer_key, hashes.SHA384())


# =====================================================================
# hypervisor -- Import hypervisor-provided certificates
# =====================================================================


def cmd_hypervisor(args: list[str]) -> int:
    """Import hypervisor-provided CA and optionally sign wildcard with it.

    Checks well-known mount paths (/mnt/pki/ca.crt, /mnt/pki/tls.key).
    If both CA cert and key are available, generates a wildcard cert
    signed by the hypervisor CA (vertical PKI).
    """
    ca_path = Path(_extract_flag(args, "--ca") or str(config.HYPERVISOR_MOUNT_CA))
    key_path = Path(_extract_flag(args, "--key") or str(config.HYPERVISOR_MOUNT_KEY))
    domain = _extract_flag(args, "--domain")
    org = _extract_flag(args, "--org")
    ou = _extract_flag(args, "--ou")
    cert_days = int(
        _extract_flag(args, "--cert-days") or config.DEFAULT_CERT_VALIDITY_DAYS
    )

    if not ca_path.exists():
        info(f"Hypervisor CA not found: {ca_path}")
        info("Nothing to import")
        return 0

    print(
        "═══════════════════════════════════════════════════════════════"
    )
    print("  Konductor PKI -- Hypervisor Certificate Import")
    print(
        "═══════════════════════════════════════════════════════════════"
    )

    identity = _load_identity(domain, org, ou)
    trust_tier = TrustTier.HYPERVISOR

    # Import hypervisor CA
    ensure_dir(config.PKI_HYPERVISOR_DIR, config.MODE_PRIVATE_DIR)
    action(f"Importing hypervisor CA from {ca_path}")
    ca_pem = ca_path.read_bytes()
    atomic_write(config.HYPERVISOR_CA_CERT, ca_pem, config.MODE_CERTIFICATE)
    ok(f"Hypervisor CA: {config.HYPERVISOR_CA_CERT}")

    if key_path.exists():
        action(f"Importing hypervisor key from {key_path}")
        key_pem = key_path.read_bytes()
        atomic_write(config.HYPERVISOR_CA_KEY, key_pem, config.MODE_PRIVATE_KEY)
        ok(f"Hypervisor key: {config.HYPERVISOR_CA_KEY}")

        # Sign wildcard cert with hypervisor CA (vertical PKI)
        if not config.VM_WILDCARD_CERT.exists() or "--force" in args:
            hyp_ca_cert = x509.load_pem_x509_certificate(ca_pem)
            hyp_ca_key = load_private_key(config.HYPERVISOR_CA_KEY)

            ensure_dir(config.PKI_VM_DIR, config.MODE_DIRECTORY)

            # Also place hypervisor CA as the VM CA for consistent paths
            atomic_write(config.VM_CA_CERT, ca_pem, config.MODE_CERTIFICATE)
            atomic_write(
                config.VM_CA_KEY, key_pem, config.MODE_PRIVATE_KEY
            )

            action("Generating wildcard key (P-256)")
            leaf_key = generate_leaf_key()
            write_private_key(
                config.VM_WILDCARD_KEY, leaf_key, config.MODE_SERVICE_KEY
            )

            action("Signing wildcard cert with hypervisor CA")
            leaf_cert = build_leaf_certificate(
                leaf_key,
                hyp_ca_key,
                hyp_ca_cert,
                identity,
                trust_tier,
                validity_days=cert_days,
            )
            # Write full chain: leaf + hypervisor CA intermediate
            chain_pem = leaf_cert.public_bytes(Encoding.PEM) + hyp_ca_cert.public_bytes(Encoding.PEM)
            atomic_write(
                config.VM_WILDCARD_CERT,
                chain_pem,
                config.MODE_CERTIFICATE,
            )
            ok(f"Wildcard cert (hypervisor-signed, chain): {config.VM_WILDCARD_CERT}")
    else:
        info(f"Hypervisor key not found: {key_path}")
        info("CA imported for trust only (no wildcard signing)")

    print()
    ok("Hypervisor import complete")
    return 0


# =====================================================================
# bundle -- Build CA trust bundle
# =====================================================================


def cmd_bundle(args: list[str]) -> int:
    """Build combined CA trust bundle from all available sources."""
    print(
        "═══════════════════════════════════════════════════════════════"
    )
    print("  Konductor PKI -- CA Bundle Generation")
    print(
        "═══════════════════════════════════════════════════════════════"
    )

    count = build_bundle()

    print()
    ok(f"Bundle complete: {count} certificates in {config.CA_BUNDLE}")
    return 0


# =====================================================================
# trust -- Install CA to system trust store
# =====================================================================


def cmd_trust(args: list[str]) -> int:
    """Install hypervisor CA to system trust store.

    Usage:
        pki trust                              Install hypervisor CA (default)
        pki trust --ca <path>                  Install specific CA file
        pki trust --docker-registry <domain>   Configure Docker trust for registry (repeatable)
        pki trust --remove                     Remove CA from system trust
        pki trust --status                     Check trust status
    """
    print(
        "═══════════════════════════════════════════════════════════════"
    )
    print("  Konductor PKI -- System Trust Management")
    print(
        "═══════════════════════════════════════════════════════════════"
    )

    # Parse arguments
    ca_path = Path(_extract_flag(args, "--ca") or str(config.HYPERVISOR_CA_CERT))
    remove = "--remove" in args
    status = "--status" in args

    # Extract all --docker-registry values
    docker_registries = []
    remaining_args = []
    i = 0
    while i < len(args):
        if args[i] == "--docker-registry" and i + 1 < len(args):
            docker_registries.append(args[i + 1])
            i += 2
        else:
            remaining_args.append(args[i])
            i += 1

    if status:
        return _trust_status(docker_registries or None)

    if remove:
        return _trust_remove()

    return _trust_install(ca_path, docker_registries)


def _trust_status(docker_registries: list[str] | None = None) -> int:
    """Check if hypervisor CA is trusted."""
    import subprocess

    bundle_path = config.CA_BUNDLE
    hypervisor_ca_path = config.HYPERVISOR_CA_CERT

    if not bundle_path.exists():
        err(f"Trust bundle not found: {bundle_path}")
        return 1

    if not hypervisor_ca_path.exists():
        info("Hypervisor CA not imported yet")
        return 1

    # Read hypervisor CA subject
    result = subprocess.run(
        ["openssl", "x509", "-in", str(hypervisor_ca_path), "-noout", "-subject"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        err("Failed to read hypervisor CA")
        return 1

    ca_subject = result.stdout.strip()

    # Check if CA is in bundle
    bundle_content = bundle_path.read_text()
    hypervisor_ca_content = hypervisor_ca_path.read_text()

    print()
    if hypervisor_ca_content in bundle_content:
        ok(f"Hypervisor CA is in bundle: {ca_subject}")
    else:
        warn(f"Hypervisor CA NOT in bundle: {ca_subject}")
        info("Run: python3 -m pki bundle")
        return 1

    # Check environment variables
    env_vars = {
        "SSL_CERT_FILE": os.environ.get("SSL_CERT_FILE"),
        "CURL_CA_BUNDLE": os.environ.get("CURL_CA_BUNDLE"),
        "GIT_SSL_CAINFO": os.environ.get("GIT_SSL_CAINFO"),
    }

    print()
    print("  Environment Variables:")
    for var, value in env_vars.items():
        if value == str(bundle_path):
            ok(f"  {var}={value}")
        elif value:
            warn(f"  {var}={value} (expected: {bundle_path})")
        else:
            info(f"  {var} not set")

    # Check Docker registry trust
    print()
    print("  Docker Registry Trust:")

    # If no registries specified, check CONTAINER_REGISTRY env or scan /etc/docker/certs.d/
    if not docker_registries:
        container_registry = os.environ.get("CONTAINER_REGISTRY")
        if container_registry:
            docker_registries = [container_registry]
        else:
            # Scan /etc/docker/certs.d/ for configured registries
            certs_d = Path("/etc/docker/certs.d")
            if certs_d.exists():
                docker_registries = [d.name for d in certs_d.iterdir() if d.is_dir()]

    if docker_registries:
        for registry in docker_registries:
            registry_ca_path = Path(f"/etc/docker/certs.d/{registry}/ca.crt")
            if registry_ca_path.exists():
                if registry_ca_path.is_symlink():
                    target = registry_ca_path.resolve()
                    if target == bundle_path:
                        ok(f"  {registry}: {registry_ca_path} → {target}")
                    else:
                        warn(f"  {registry}: {registry_ca_path} → {target} (expected: {bundle_path})")
                else:
                    info(f"  {registry}: {registry_ca_path} (not a symlink)")
            else:
                info(f"  {registry}: not configured")
    else:
        info("  No Docker registries configured")

    return 0


def _trust_install(ca_path: Path, docker_registries: list[str] | None = None) -> int:
    """Install CA to system trust."""
    if not ca_path.exists():
        err(f"CA file not found: {ca_path}")
        return 1

    print()
    action(f"Installing CA to system trust: {ca_path}")

    # 1. Ensure CA is in hypervisor directory
    if ca_path != config.HYPERVISOR_CA_CERT:
        action(f"Copying CA to {config.HYPERVISOR_CA_CERT}")
        ensure_dir(config.PKI_HYPERVISOR_DIR, config.MODE_PRIVATE_DIR)
        atomic_write(config.HYPERVISOR_CA_CERT, ca_path.read_bytes(), config.MODE_CERTIFICATE)
        ok(f"CA copied: {config.HYPERVISOR_CA_CERT}")

    # 2. Rebuild bundle (includes hypervisor CA)
    action("Rebuilding trust bundle")
    cert_count = build_bundle()
    ok(f"Bundle updated: {cert_count} certificates")

    # 3. Install environment variables
    action("Installing environment variables")
    _install_env_vars()
    ok("Environment variables installed: /etc/profile.d/konductor-ca.sh")

    # 4. Configure Docker registry trust (if registries specified or env set)
    if not docker_registries:
        container_registry = os.environ.get("CONTAINER_REGISTRY")
        if container_registry:
            docker_registries = [container_registry]

    if docker_registries:
        action(f"Configuring Docker registry trust for: {', '.join(docker_registries)}")
        _install_docker_trust(docker_registries)
        ok(f"Docker registry trust configured: {', '.join(docker_registries)}")

        # Restart Docker daemon (if running)
        import subprocess
        result = subprocess.run(
            ["systemctl", "is-active", "docker.service"],
            capture_output=True,
        )
        if result.returncode == 0:
            action("Restarting Docker daemon")
            try:
                subprocess.run(["systemctl", "restart", "docker.service"], check=True)
                ok("Docker daemon restarted")
            except subprocess.CalledProcessError as exc:
                warn(f"Failed to restart Docker: {exc}")
    else:
        info("No Docker registries specified (use --docker-registry or CONTAINER_REGISTRY env)")

    print()
    ok("System trust installation complete")
    info("Restart shells to load new environment variables")

    return 0


def _trust_remove() -> int:
    """Remove CA from system trust."""
    print()
    action("Removing CA from system trust")

    # 1. Remove environment variables
    env_file = Path("/etc/profile.d/konductor-ca.sh")
    if env_file.exists():
        env_file.unlink()
        ok(f"Removed: {env_file}")

    # 2. Remove Docker registry trust
    registry_ca_dir = Path("/etc/docker/certs.d/registry.ucs.arpa")
    if registry_ca_dir.exists():
        import shutil
        shutil.rmtree(registry_ca_dir)
        ok(f"Removed: {registry_ca_dir}")

    # 3. Rebuild bundle without hypervisor CA
    if config.HYPERVISOR_CA_CERT.exists():
        config.HYPERVISOR_CA_CERT.unlink()
    cert_count = build_bundle()
    ok(f"Bundle rebuilt without hypervisor CA: {cert_count} certificates")

    print()
    ok("System trust removal complete")

    return 0


def _install_env_vars() -> None:
    """Install environment variables for TLS trust."""
    bundle_path = config.CA_BUNDLE

    env_script = f"""# Konductor PKI Trust Bundle
# Auto-generated by konductor-pki-trust.service
# Do not edit manually

export SSL_CERT_FILE="${{SSL_CERT_FILE:-{bundle_path}}}"
export NIX_SSL_CERT_FILE="${{NIX_SSL_CERT_FILE:-{bundle_path}}}"
export CURL_CA_BUNDLE="${{CURL_CA_BUNDLE:-{bundle_path}}}"
export REQUESTS_CA_BUNDLE="${{REQUESTS_CA_BUNDLE:-{bundle_path}}}"
export NODE_EXTRA_CA_CERTS="${{NODE_EXTRA_CA_CERTS:-{bundle_path}}}"
export GIT_SSL_CAINFO="${{GIT_SSL_CAINFO:-{bundle_path}}}"
"""

    env_file = Path("/etc/profile.d/konductor-ca.sh")
    env_file.parent.mkdir(parents=True, exist_ok=True)
    env_file.write_text(env_script)
    env_file.chmod(0o644)


def _install_docker_trust(docker_registries: list[str]) -> None:
    """Configure Docker to trust registries with custom CA.

    Args:
        docker_registries: List of registry domains (e.g., ["registry.ucs.arpa", "docker.io"])
    """
    bundle_path = config.CA_BUNDLE

    # Docker per-registry CA configuration
    # https://docs.docker.com/engine/security/certificates/
    for registry in docker_registries:
        registry_ca_dir = Path(f"/etc/docker/certs.d/{registry}")
        registry_ca_dir.mkdir(parents=True, exist_ok=True)

        registry_ca_link = registry_ca_dir / "ca.crt"

        # Remove old symlink if exists
        if registry_ca_link.exists() or registry_ca_link.is_symlink():
            registry_ca_link.unlink()

        # Create symlink to bundle
        registry_ca_link.symlink_to(bundle_path)


# =====================================================================
# inspect -- Show certificate provenance
# =====================================================================


def cmd_inspect(args: list[str]) -> int:
    """Inspect certificate and display provenance extensions."""
    cert_path = Path(args[0]) if args else config.VM_CA_CERT

    if not cert_path.exists():
        err(f"Certificate not found: {cert_path}")
        return 1

    cert = x509.load_pem_x509_certificate(cert_path.read_bytes())

    print(
        "═══════════════════════════════════════════════════════════════"
    )
    print(f"  Certificate: {cert_path}")
    print(
        "═══════════════════════════════════════════════════════════════"
    )
    _print_cert_summary("", cert)

    # Extract custom OID extensions
    print()
    print("  Provenance Extensions:")
    found = False
    for ext in cert.extensions:
        oid_str = ext.oid.dotted_string
        name = config.OID_NAMES.get(oid_str)
        if name:
            value = decode_provenance_value(ext.value.value)
            info(f"{name}: {value}")
            found = True

    if not found:
        info("No Konductor provenance extensions found")

    # Show nsComment if present
    ns_oid = config.NS_COMMENT_OID
    for ext in cert.extensions:
        if ext.oid.dotted_string == ns_oid:
            raw = ext.value.value
            # Decode IA5String: skip tag (0x16) + length bytes
            if raw and raw[0] == 0x16:
                if raw[1] < 0x80:
                    comment = raw[2:].decode("ascii", errors="replace")
                elif raw[1] == 0x81:
                    comment = raw[3:].decode("ascii", errors="replace")
                else:
                    comment = raw[4:].decode("ascii", errors="replace")
                print()
                info(f"nsComment: {comment}")

    # Show SANs
    try:
        san_ext = cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        )
        print()
        print("  Subject Alternative Names:")
        for dns in san_ext.value.get_values_for_type(x509.DNSName):
            info(f"DNS: {dns}")
        for uri in san_ext.value.get_values_for_type(
            x509.UniformResourceIdentifier
        ):
            info(f"URI: {uri}")
    except x509.ExtensionNotFound:
        pass

    return 0


# =====================================================================
# status -- Single command for full PKI state
# =====================================================================


def cmd_status(args: list[str]) -> int:
    """Check every PKI file, dump public metadata for each cert found.

    One command, run anywhere (build host, inside VM, CI), gives full
    picture of PKI state. Same output everywhere = easy to compare.
    """
    print(
        "═══════════════════════════════════════════════════════════════"
    )
    print("  Konductor PKI Status")
    print(
        "═══════════════════════════════════════════════════════════════"
    )

    # All files we ever create, grouped by tier
    files = [
        ("VM CA cert",       config.VM_CA_CERT,        True),
        ("VM CA key",        config.VM_CA_KEY,          False),
        ("VM wildcard cert", config.VM_WILDCARD_CERT,   True),
        ("VM wildcard key",  config.VM_WILDCARD_KEY,    False),
        ("Hypervisor CA",    config.HYPERVISOR_CA_CERT, True),
        ("Hypervisor key",   config.HYPERVISOR_CA_KEY,  False),
        ("CA bundle",        config.CA_BUNDLE,          False),
        ("Cluster CA",       config.CLUSTER_CA,         True),
    ]

    # Also check mount points (deploy-time only)
    mount_points = [
        ("Hypervisor mount CA",  config.HYPERVISOR_MOUNT_CA),
        ("Hypervisor mount key", config.HYPERVISOR_MOUNT_KEY),
    ]

    print()
    print("  Files:")
    for label, path, is_cert in files:
        if path.exists():
            ok(f"{label}: {path}")
        else:
            info(f"{label}: not found")

    for label, path in mount_points:
        if path.exists():
            ok(f"{label}: {path}")
        else:
            info(f"{label}: not found")

    # Bundle cert count
    if config.CA_BUNDLE.exists():
        count = config.CA_BUNDLE.read_text().count("BEGIN CERTIFICATE")
        info(f"Bundle contains {count} certificate(s)")

    # Dump public metadata for every cert that exists
    for label, path, is_cert in files:
        if not is_cert or not path.exists():
            continue
        print()
        print(f"  {label}: {path}")
        _dump_cert(path)

    # Build fingerprint
    print()
    print("  Build Fingerprint (/.konductor):")
    fp: Fingerprint | None = None
    if config.FINGERPRINT_PATH.exists():
        try:
            fp = Fingerprint.load()
        except FingerprintError as exc:
            err(f"CORRUPT: {exc}")
            print()
            return 1

        if fp.is_ephemeral:
            err("ORPHANED: /.konductor exists but contains no provenance data")
        else:
            ok(f"Parsed: {config.FINGERPRINT_PATH}")
            info(f"git_commit:       {fp.git_commit}")
            info(f"git_branch:       {fp.git_branch}")
            info(f"git_remote:       {fp.git_remote}")
            info(f"nix_drv:          {fp.nix_drv}")
            info(f"nix_hash:         {fp.nix_hash}")
            info(f"build_date:       {fp.build_date}")
            info(f"build_host:       {fp.build_host}")
            info(f"build_user:       {fp.build_user}")
            if fp.build_hw_vendor:
                info(f"build_hw_vendor:  {fp.build_hw_vendor}")
            if fp.build_hw_product:
                info(f"build_hw_product: {fp.build_hw_product}")
            if fp.build_hw_serial:
                info(f"build_hw_serial:  {fp.build_hw_serial}")
    else:
        err("ORPHANED: /.konductor not found (pre-provenance)")

    # Self-discovery from source tree
    print()
    print("  Source Tree Discovery:")
    src_exists = config.SOURCE_TREE.exists()
    if src_exists:
        try:
            discovered = Fingerprint.discover()
            if discovered.git_commit:
                ok(f"git_commit:        {discovered.git_commit}")
            if discovered.flake_lock_sha256:
                ok(f"flake_lock_sha256: {discovered.flake_lock_sha256}")
        except FingerprintError as exc:
            err(f"Discovery failed: {exc}")
            discovered = None
    else:
        info(f"Source tree not found at {config.SOURCE_TREE}")
        discovered = None

    # Cross-validate baked vs discovered
    if fp is not None and not fp.is_ephemeral and discovered is not None:
        errors = fp.validate_against(discovered)
        print()
        if errors:
            print("  ⚠ Provenance Validation: FAILED")
            for e in errors:
                err(e)
        else:
            print("  Provenance Validation: PASSED")
            ok("Baked /.konductor matches source tree self-discovery")

    print()
    return 0


def _dump_cert(path: Path) -> None:
    """Dump all public-safe metadata for a single certificate."""
    cert = x509.load_pem_x509_certificate(path.read_bytes())

    # Subject and issuer
    info(f"Subject: {cert.subject.rfc4514_string()}")
    info(f"Issuer:  {cert.issuer.rfc4514_string()}")

    # Validity
    not_before = cert.not_valid_before_utc.strftime("%Y-%m-%d %H:%M:%S UTC")
    not_after = cert.not_valid_after_utc.strftime("%Y-%m-%d %H:%M:%S UTC")
    info(f"Valid:   {not_before} to {not_after}")

    # Serial number
    info(f"Serial:  {cert.serial_number:#x}")

    # SHA-256 fingerprint of the cert itself (what browsers show)
    sha256_fp = cert.fingerprint(SHA256()).hex(":")
    info(f"SHA-256: {sha256_fp}")

    # Key type and curve
    pub = cert.public_key()
    if isinstance(pub, EllipticCurvePublicKey):
        info(f"Key:     EC {pub.curve.name} ({pub.key_size}-bit)")

    # Basic constraints
    try:
        bc = cert.extensions.get_extension_for_class(x509.BasicConstraints)
        ca_str = "CA:TRUE" if bc.value.ca else "CA:FALSE"
        info(f"Basic:   {ca_str}")
    except x509.ExtensionNotFound:
        pass

    # SANs
    try:
        san = cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        )
        dns_names = san.value.get_values_for_type(x509.DNSName)
        if dns_names:
            info(f"DNS:     {', '.join(dns_names)}")
        uri_names = san.value.get_values_for_type(
            x509.UniformResourceIdentifier
        )
        for uri in uri_names:
            info(f"URI:     {uri}")
    except x509.ExtensionNotFound:
        pass

    # nsComment
    for ext in cert.extensions:
        if ext.oid.dotted_string == config.NS_COMMENT_OID:
            raw = ext.value.value
            if raw and raw[0] == 0x16:
                offset = 2 if raw[1] < 0x80 else (3 if raw[1] == 0x81 else 4)
                comment = raw[offset:].decode("ascii", errors="replace")
                info(f"Comment: {comment}")

    # Custom OID provenance extensions
    for ext in cert.extensions:
        name = config.OID_NAMES.get(ext.oid.dotted_string)
        if name:
            value = decode_provenance_value(ext.value.value)
            info(f"{name}: {value}")


# =====================================================================
# Helpers
# =====================================================================


def _extract_flag(args: list[str], flag: str) -> str | None:
    """Extract --flag value from args list, removing both flag and value."""
    try:
        idx = args.index(flag)
        if idx + 1 < len(args):
            value = args[idx + 1]
            del args[idx : idx + 2]
            return value
        del args[idx]
    except ValueError:
        pass
    return None


def _print_cert_summary(label: str, cert: x509.Certificate) -> None:
    """Print certificate subject, issuer, validity."""
    prefix = f"  {label} " if label else "  "
    subject = cert.subject.rfc4514_string()
    issuer = cert.issuer.rfc4514_string()
    not_before = cert.not_valid_before_utc.strftime("%Y-%m-%d")
    not_after = cert.not_valid_after_utc.strftime("%Y-%m-%d")
    info(f"{prefix}Subject: {subject}")
    info(f"{prefix}Issuer:  {issuer}")
    info(f"{prefix}Valid:   {not_before} to {not_after}")


USAGE = """\
Usage: python3 -m pki <command> [options]

Commands:
  generate    Generate CA + wildcard cert (idempotent)
  hypervisor  Import hypervisor-provided certificates
  bundle      Build CA trust bundle
  trust       Install CA to system trust store (Docker, Git, etc.)
  inspect     Inspect certificate provenance
  status      Show PKI status summary

Options (generate/hypervisor):
  --domain <domain>     Certificate domain (default: konductor.arpa)
  --org <organization>  Organization name (default: Konductor)
  --ou <unit>           Organizational unit (default: Infrastructure)
  --ca-days <days>      CA validity in days (default: 3650)
  --cert-days <days>    Leaf cert validity in days (default: 365)
  --force               Regenerate even if certs exist

Options (trust):
  --ca <path>                  CA file to install (default: hypervisor CA)
  --docker-registry <domain>   Configure Docker trust for registry (repeatable)
  --remove                     Remove CA from system trust
  --status                     Check trust status

Options (inspect):
  <path>                Certificate file to inspect (default: VM CA cert)
"""

COMMANDS = {
    "generate": cmd_generate,
    "hypervisor": cmd_hypervisor,
    "bundle": cmd_bundle,
    "trust": cmd_trust,
    "inspect": cmd_inspect,
    "status": cmd_status,
}


def run() -> int:
    """CLI entry point. Returns exit code."""
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help", "help"):
        print(USAGE)
        return 0

    command = args[0]
    if command not in COMMANDS:
        err(f"Unknown command: {command}")
        print(USAGE, file=sys.stderr)
        return 1

    try:
        return COMMANDS[command](args[1:])
    except KeyboardInterrupt:
        print()
        return 130
    except Exception as exc:
        err(f"{type(exc).__name__}: {exc}")
        return 1
