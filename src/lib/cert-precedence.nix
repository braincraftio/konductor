{ pkgs }:

pkgs.writeShellScriptBin "konductor-find-best-cert" ''
  #!/usr/bin/env bash
  # Certificate precedence detection for Konductor services
  # Returns: CERT_PATH=... and KEY_PATH=... and CERT_TIER=... to stdout
  # Exit code: 0=success (valid cert found), 1=no valid cert found
  #
  # Precedence (highest to lowest priority):
  #   Tier 1: /mnt/pki/wildcard.{crt,key} (cluster-provided via volume mount)
  #   Tier 2: /etc/konductor/pki/signed/wildcard.{crt,key} (VM-signed with hypervisor CA)
  #   Tier 3: /etc/konductor/pki/vm/wildcard.{crt,key} (self-signed fallback)

  set -euo pipefail

  # Define precedence order (highest to lowest priority)
  # Format: cert_path:key_path:tier_name
  CERT_TIERS=(
    "/mnt/pki/wildcard.crt:/mnt/pki/wildcard.key:cluster-provided"
    "/etc/konductor/pki/signed/wildcard.crt:/etc/konductor/pki/signed/wildcard.key:hypervisor-signed"
    "/etc/konductor/pki/vm/wildcard.crt:/etc/konductor/pki/vm/wildcard.key:self-signed"
  )

  check_cert_valid() {
    local cert=$1
    local key=$2

    # Check files exist and are readable
    [ -f "$cert" ] && [ -r "$cert" ] || return 1
    [ -f "$key" ] && [ -r "$key" ] || return 1

    # Check cert is not expired (redirect stdout too - openssl prints "Certificate will not expire")
    ${pkgs.openssl}/bin/openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1 || return 1

    # Check key type matches cert (both EC or both RSA)
    cert_text=$(${pkgs.openssl}/bin/openssl x509 -in "$cert" -noout -text 2>/dev/null) || return 1

    if echo "$cert_text" | ${pkgs.gnugrep}/bin/grep -q "Public Key Algorithm: id-ecPublicKey"; then
      # EC key - verify it's readable as EC key
      ${pkgs.openssl}/bin/openssl ec -in "$key" -noout 2>/dev/null || return 1
    else
      # RSA key - verify it's readable as RSA key
      ${pkgs.openssl}/bin/openssl rsa -in "$key" -noout 2>/dev/null || return 1
    fi

    return 0
  }

  # Try each tier in order
  for tier in "''${CERT_TIERS[@]}"; do
    IFS=':' read -r cert key name <<< "$tier"

    if check_cert_valid "$cert" "$key"; then
      echo "CERT_PATH=$cert"
      echo "KEY_PATH=$key"
      echo "CERT_TIER=$name"
      exit 0
    fi
  done

  # No valid certificate found - this is fatal
  echo "ERROR: No valid certificate found in any tier" >&2
  exit 1
''
