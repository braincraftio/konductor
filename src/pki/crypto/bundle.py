"""CA bundle aggregation.

Creates a combined trust bundle from all available certificate sources:
  1. System CAs (/etc/ssl/certs/ca-certificates.crt)
  2. VM CA (/etc/konductor/pki/vm/ca.crt)
  3. Hypervisor CA (/etc/konductor/pki/hypervisor/ca.crt)
  4. Cloud-init cluster CA (/etc/konductor/cluster-ca.crt)

Output path: /etc/konductor/pki/bundle/ca-bundle.crt
This is THE canonical bundle path. All consumers use this path.
"""

from __future__ import annotations

from pathlib import Path

from pki import config
from pki.utils import action, atomic_write, ensure_dir, info, ok


def build_bundle(
    output: Path | None = None,
    system_ca: Path | None = None,
    vm_ca: Path | None = None,
    hypervisor_ca: Path | None = None,
    cluster_ca: Path | None = None,
) -> int:
    """Build CA trust bundle from all available sources.

    Returns:
        Number of CA certificates in the bundle.
    """
    output = output or config.CA_BUNDLE
    system_ca = system_ca or config.SYSTEM_CA
    vm_ca = vm_ca or config.VM_CA_CERT
    hypervisor_ca = hypervisor_ca or config.HYPERVISOR_CA_CERT
    cluster_ca = cluster_ca or config.CLUSTER_CA

    ensure_dir(output.parent, config.MODE_DIRECTORY)

    parts: list[str] = []
    cert_count = 0

    # System CAs (base trust store)
    if system_ca.exists():
        content = system_ca.read_text()
        parts.append(content)
        count = content.count("BEGIN CERTIFICATE")
        cert_count += count
        info(f"System CAs: {count} certificates")
    else:
        info("System CAs: not found (skipped)")

    # VM CA
    if vm_ca.exists():
        parts.append(f"\n# Konductor VM CA\n{vm_ca.read_text()}")
        cert_count += 1
        ok(f"VM CA: {vm_ca}")
    else:
        info("VM CA: not generated yet (skipped)")

    # Hypervisor CA
    if hypervisor_ca.exists():
        parts.append(f"\n# Konductor Hypervisor CA\n{hypervisor_ca.read_text()}")
        cert_count += 1
        ok(f"Hypervisor CA: {hypervisor_ca}")
    else:
        info("Hypervisor CA: not mounted (skipped)")

    # Cloud-init cluster CA
    if cluster_ca.exists():
        parts.append(f"\n# Cloud-init Cluster CA\n{cluster_ca.read_text()}")
        cert_count += 1
        ok(f"Cluster CA: {cluster_ca}")
    else:
        info("Cluster CA: not injected (skipped)")

    if not parts:
        info("No CA certificates found, creating empty bundle")
        bundle_content = ""
    else:
        bundle_content = "".join(parts)
        if not bundle_content.endswith("\n"):
            bundle_content += "\n"

    action(f"Writing bundle: {output}")
    atomic_write(output, bundle_content.encode("utf-8"), config.MODE_CERTIFICATE)
    ok(f"CA bundle: {cert_count} certificates in {output}")

    return cert_count
