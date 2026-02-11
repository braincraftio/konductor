"""Konductor PKI -- Fingerprint-derived certificate chain of trust.

Generates X.509 certificates with build provenance embedded as custom OID
extensions. Supports three trust tiers: hypervisor-provided, cloud-init
injected, and self-signed from /.konductor build fingerprint.

Trust hierarchy (highest to lowest):
  1. Hypervisor CA -- mounted from parent cluster via KubeVirt volume
  2. Cloud-init CA -- injected via deploy-time userdata
  3. Self-signed   -- generated from build fingerprint (always available)
"""

__version__ = "2.0.0"
