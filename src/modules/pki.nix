# src/modules/pki.nix
# Konductor PKI - VM identity and certificate chain of trust
#
# Provides two certificate authorities:
# 1. VM-local CA: Self-generated identity for the VM (*.konductor.arpa or custom FQDN)
# 2. Hypervisor CA: Mounted from parent cluster (cloud-init or volume mount)
#
# Both coexist and can be used independently by downstream consumers (Pulumi, etc.)
#
# Directory structure:
#   /etc/konductor/pki/
#   ├── vm/                 # VM-local identity (generated on first boot)
#   │   ├── ca.crt          # VM CA certificate
#   │   ├── ca.key          # VM CA private key
#   │   ├── wildcard.crt    # Wildcard certificate for VM FQDN
#   │   └── wildcard.key    # Wildcard private key
#   ├── hypervisor/         # Mounted from parent (optional)
#   │   ├── ca.crt          # Parent cluster CA certificate
#   │   └── ca.key          # Parent cluster CA key (optional)
#   └── bundle/
#       └── ca-bundle.crt   # Combined: system + vm + hypervisor CAs
#
# Usage in Pulumi:
#   ca_source: "provided"
#   ca_certificate_base64: $(base64 -w0 /etc/konductor/pki/vm/ca.crt)
#   ca_private_key_base64: $(base64 -w0 /etc/konductor/pki/vm/ca.key)

{ config, lib, pkgs, ... }:

let
  cfg = config.konductor.pki;

  # Default domain based on hostname or fallback
  defaultDomain = if config.networking.hostName != "localhost"
    then "${config.networking.hostName}.arpa"
    else "konductor.arpa";

in {
  options.konductor.pki = {
    enable = lib.mkEnableOption "Konductor PKI provisioning";

    domain = lib.mkOption {
      type = lib.types.str;
      default = defaultDomain;
      description = ''
        Domain for VM identity certificates.
        Default: {hostname}.arpa (e.g., konductor.arpa)
        Wildcard cert will be generated as *.{domain}
      '';
    };

    organization = lib.mkOption {
      type = lib.types.str;
      default = "Konductor";
      description = "Organization name for CA certificate subject";
    };

    organizationalUnit = lib.mkOption {
      type = lib.types.str;
      default = "Infrastructure";
      description = "Organizational unit for CA certificate subject";
    };

    caValidityDays = lib.mkOption {
      type = lib.types.int;
      default = 3650;  # 10 years
      description = "Validity period for CA certificate in days";
    };

    certValidityDays = lib.mkOption {
      type = lib.types.int;
      default = 365;  # 1 year
      description = "Validity period for wildcard certificate in days";
    };

    keyAlgorithm = lib.mkOption {
      type = lib.types.enum [ "ec" "rsa" ];
      default = "ec";
      description = "Key algorithm: ec (prime256v1) or rsa (4096-bit)";
    };

    hypervisorCaPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to hypervisor CA certificate (mounted from parent cluster).
        If null, only VM-local CA is used.
        Can be set via cloud-init or volume mount.
      '';
    };

    hypervisorKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to hypervisor CA private key (optional).
        Only needed if VM should sign certs as intermediate CA.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure openssl is available
    environment.systemPackages = [ pkgs.openssl ];

    # Create PKI directory structure
    systemd.tmpfiles.rules = [
      "d /etc/konductor/pki 0755 root root -"
      "d /etc/konductor/pki/vm 0700 root root -"
      "d /etc/konductor/pki/hypervisor 0700 root root -"
      "d /etc/konductor/pki/bundle 0755 root root -"
    ];

    systemd.services = {
      # =====================================================================
      # VM-local CA Generation
      # =====================================================================
      # Generates self-signed CA and wildcard certificate on first boot.
      # Idempotent: only runs if ca.crt doesn't exist.
      konductor-pki-vm = {
        description = "Generate Konductor VM-local PKI";
        after = [ "local-fs.target" ];
        before = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        unitConfig = {
          # Only run if CA doesn't exist (first boot)
          ConditionPathExists = "!/etc/konductor/pki/vm/ca.crt";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "generate-vm-pki" ''
            set -euo pipefail

            PKI_DIR="/etc/konductor/pki/vm"
            DOMAIN="${cfg.domain}"
            ORG="${cfg.organization}"
            OU="${cfg.organizationalUnit}"
            CA_DAYS=${toString cfg.caValidityDays}
            CERT_DAYS=${toString cfg.certValidityDays}

            echo "Generating Konductor VM PKI for domain: $DOMAIN"

            # Ensure directory exists with correct permissions
            mkdir -p "$PKI_DIR"
            chmod 700 "$PKI_DIR"

            # Generate CA private key
            ${if cfg.keyAlgorithm == "ec" then ''
              ${pkgs.openssl}/bin/openssl ecparam -genkey -name prime256v1 -noout \
                -out "$PKI_DIR/ca.key"
            '' else ''
              ${pkgs.openssl}/bin/openssl genrsa -out "$PKI_DIR/ca.key" 4096
            ''}
            chmod 600 "$PKI_DIR/ca.key"

            # Generate CA certificate
            ${pkgs.openssl}/bin/openssl req -new -x509 \
              -key "$PKI_DIR/ca.key" \
              -sha256 \
              -days "$CA_DAYS" \
              -subj "/O=$ORG/OU=$OU/CN=$DOMAIN Root CA" \
              -out "$PKI_DIR/ca.crt"
            chmod 644 "$PKI_DIR/ca.crt"

            echo "Generated CA: /O=$ORG/OU=$OU/CN=$DOMAIN Root CA"

            # Generate wildcard certificate private key
            ${if cfg.keyAlgorithm == "ec" then ''
              ${pkgs.openssl}/bin/openssl ecparam -genkey -name prime256v1 -noout \
                -out "$PKI_DIR/wildcard.key"
            '' else ''
              ${pkgs.openssl}/bin/openssl genrsa -out "$PKI_DIR/wildcard.key" 4096
            ''}
            chmod 600 "$PKI_DIR/wildcard.key"

            # Create CSR config with SANs
            cat > "$PKI_DIR/wildcard.cnf" << EOF
            [req]
            distinguished_name = req_distinguished_name
            req_extensions = v3_req
            prompt = no

            [req_distinguished_name]
            O = $ORG
            OU = $OU
            CN = *.$DOMAIN

            [v3_req]
            keyUsage = critical, digitalSignature, keyEncipherment
            extendedKeyUsage = serverAuth, clientAuth
            subjectAltName = @alt_names

            [alt_names]
            DNS.1 = *.$DOMAIN
            DNS.2 = $DOMAIN
            DNS.3 = *.docker.$DOMAIN
            DNS.4 = docker.$DOMAIN
            EOF

            # Generate CSR
            ${pkgs.openssl}/bin/openssl req -new \
              -key "$PKI_DIR/wildcard.key" \
              -config "$PKI_DIR/wildcard.cnf" \
              -out "$PKI_DIR/wildcard.csr"

            # Sign wildcard certificate
            # Use hypervisor CA if mounted (vertical PKI), otherwise use VM CA
            ${if (cfg.hypervisorCaPath != null && cfg.hypervisorKeyPath != null) then ''
              if [ -f "${toString cfg.hypervisorCaPath}" ] && [ -f "${toString cfg.hypervisorKeyPath}" ]; then
                echo "Signing wildcard cert with hypervisor CA (vertical PKI)"
                ${pkgs.openssl}/bin/openssl x509 -req \
                  -in "$PKI_DIR/wildcard.csr" \
                  -CA "${toString cfg.hypervisorCaPath}" \
                  -CAkey "${toString cfg.hypervisorKeyPath}" \
                  -CAcreateserial \
                  -out "$PKI_DIR/wildcard.crt" \
                  -days "$CERT_DAYS" \
                  -sha256 \
                  -extfile "$PKI_DIR/wildcard.cnf" \
                  -extensions v3_req
              else
                echo "Hypervisor CA configured but not available, using VM CA (self-signed)"
                ${pkgs.openssl}/bin/openssl x509 -req \
                  -in "$PKI_DIR/wildcard.csr" \
                  -CA "$PKI_DIR/ca.crt" \
                  -CAkey "$PKI_DIR/ca.key" \
                  -CAcreateserial \
                  -out "$PKI_DIR/wildcard.crt" \
                  -days "$CERT_DAYS" \
                  -sha256 \
                  -extfile "$PKI_DIR/wildcard.cnf" \
                  -extensions v3_req
              fi
            '' else ''
              echo "Using VM CA (self-signed)"
              ${pkgs.openssl}/bin/openssl x509 -req \
                -in "$PKI_DIR/wildcard.csr" \
                -CA "$PKI_DIR/ca.crt" \
                -CAkey "$PKI_DIR/ca.key" \
                -CAcreateserial \
                -out "$PKI_DIR/wildcard.crt" \
                -days "$CERT_DAYS" \
                -sha256 \
                -extfile "$PKI_DIR/wildcard.cnf" \
                -extensions v3_req
            ''}
            chmod 644 "$PKI_DIR/wildcard.crt"

            # Cleanup CSR and config (not needed after signing)
            rm -f "$PKI_DIR/wildcard.csr" "$PKI_DIR/wildcard.cnf" "$PKI_DIR/ca.srl"

            echo "Generated wildcard certificate: *.$DOMAIN"
            echo "VM PKI generation complete"

            # Display certificate info
            ${pkgs.openssl}/bin/openssl x509 -in "$PKI_DIR/ca.crt" -noout -subject -issuer -dates
          '';
        };
      };

      # =====================================================================
      # Hypervisor CA Import (if mounted)
      # =====================================================================
      # Copies hypervisor CA from mount point to PKI directory.
      # Runs after cloud-init in case CA is injected via user-data.
      konductor-pki-hypervisor = lib.mkIf (cfg.hypervisorCaPath != null) {
        description = "Import Konductor hypervisor CA";
        after = [ "local-fs.target" "cloud-init.service" ];
        wantedBy = [ "multi-user.target" ];

        unitConfig = {
          ConditionPathExists = toString cfg.hypervisorCaPath;
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "import-hypervisor-pki" ''
            set -euo pipefail

            SRC_CA="${toString cfg.hypervisorCaPath}"
            DST_DIR="/etc/konductor/pki/hypervisor"

            echo "Importing hypervisor CA from $SRC_CA"

            mkdir -p "$DST_DIR"
            chmod 700 "$DST_DIR"

            cp "$SRC_CA" "$DST_DIR/ca.crt"
            chmod 644 "$DST_DIR/ca.crt"

            ${lib.optionalString (cfg.hypervisorKeyPath != null) ''
              if [ -f "${toString cfg.hypervisorKeyPath}" ]; then
                cp "${toString cfg.hypervisorKeyPath}" "$DST_DIR/ca.key"
                chmod 600 "$DST_DIR/ca.key"
                echo "Imported hypervisor CA key"
              fi
            ''}

            echo "Hypervisor CA imported"
            ${pkgs.openssl}/bin/openssl x509 -in "$DST_DIR/ca.crt" -noout -subject -issuer -dates
          '';
        };
      };

      # =====================================================================
      # CA Bundle Generation
      # =====================================================================
      # Creates combined trust bundle from all available CAs.
      # Runs after VM and hypervisor CA services.
      konductor-pki-bundle = {
        description = "Generate Konductor CA bundle";
        after = [
          "konductor-pki-vm.service"
        ] ++ lib.optional (cfg.hypervisorCaPath != null) "konductor-pki-hypervisor.service";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "generate-ca-bundle" ''
            set -euo pipefail

            BUNDLE_DIR="/etc/konductor/pki/bundle"
            BUNDLE_FILE="$BUNDLE_DIR/ca-bundle.crt"
            SYSTEM_CA="/etc/ssl/certs/ca-certificates.crt"
            VM_CA="/etc/konductor/pki/vm/ca.crt"
            HYPERVISOR_CA="/etc/konductor/pki/hypervisor/ca.crt"

            echo "Generating Konductor CA bundle"

            mkdir -p "$BUNDLE_DIR"

            # Start with system CAs
            if [ -f "$SYSTEM_CA" ]; then
              cp "$SYSTEM_CA" "$BUNDLE_FILE"
            else
              touch "$BUNDLE_FILE"
            fi

            # Append VM CA
            if [ -f "$VM_CA" ]; then
              echo "" >> "$BUNDLE_FILE"
              echo "# Konductor VM CA" >> "$BUNDLE_FILE"
              cat "$VM_CA" >> "$BUNDLE_FILE"
              echo "Added VM CA to bundle"
            fi

            # Append hypervisor CA if present
            if [ -f "$HYPERVISOR_CA" ]; then
              echo "" >> "$BUNDLE_FILE"
              echo "# Konductor Hypervisor CA" >> "$BUNDLE_FILE"
              cat "$HYPERVISOR_CA" >> "$BUNDLE_FILE"
              echo "Added hypervisor CA to bundle"
            fi

            # Also check for cloud-init injected CA (backward compatibility)
            if [ -f "/etc/konductor/cluster-ca.crt" ]; then
              echo "" >> "$BUNDLE_FILE"
              echo "# Cloud-init Cluster CA" >> "$BUNDLE_FILE"
              cat "/etc/konductor/cluster-ca.crt" >> "$BUNDLE_FILE"
              echo "Added cloud-init cluster CA to bundle"
            fi

            chmod 644 "$BUNDLE_FILE"

            # Count certificates in bundle
            CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$BUNDLE_FILE" || echo "0")
            echo "CA bundle generated with $CERT_COUNT certificates: $BUNDLE_FILE"
          '';
        };
      };
    };

    # Environment variables pointing to PKI paths
    environment.variables = {
      KONDUCTOR_VM_CA_CERT = "/etc/konductor/pki/vm/ca.crt";
      KONDUCTOR_VM_CA_KEY = "/etc/konductor/pki/vm/ca.key";
      KONDUCTOR_VM_WILDCARD_CERT = "/etc/konductor/pki/vm/wildcard.crt";
      KONDUCTOR_VM_WILDCARD_KEY = "/etc/konductor/pki/vm/wildcard.key";
      KONDUCTOR_CA_BUNDLE = "/etc/konductor/pki/bundle/ca-bundle.crt";
    };

    # Profile script for easy access
    environment.etc."profile.d/konductor-pki.sh".text = ''
      # Konductor PKI environment
      export KONDUCTOR_VM_CA_CERT="/etc/konductor/pki/vm/ca.crt"
      export KONDUCTOR_VM_CA_KEY="/etc/konductor/pki/vm/ca.key"
      export KONDUCTOR_VM_WILDCARD_CERT="/etc/konductor/pki/vm/wildcard.crt"
      export KONDUCTOR_VM_WILDCARD_KEY="/etc/konductor/pki/vm/wildcard.key"
      export KONDUCTOR_CA_BUNDLE="/etc/konductor/pki/bundle/ca-bundle.crt"

      # Helpers for Pulumi integration
      konductor-ca-base64() {
        if [ -f "$KONDUCTOR_VM_CA_CERT" ] && [ -f "$KONDUCTOR_VM_CA_KEY" ]; then
          echo "ca_certificate_base64: $(base64 -w0 "$KONDUCTOR_VM_CA_CERT")"
          echo "ca_private_key_base64: $(base64 -w0 "$KONDUCTOR_VM_CA_KEY")"
        else
          echo "Error: VM CA not generated yet" >&2
          return 1
        fi
      }

      konductor-ca-info() {
        echo "=== VM CA ==="
        if [ -f "$KONDUCTOR_VM_CA_CERT" ]; then
          openssl x509 -in "$KONDUCTOR_VM_CA_CERT" -noout -subject -issuer -dates -fingerprint
        else
          echo "Not generated"
        fi

        echo ""
        echo "=== Hypervisor CA ==="
        if [ -f "/etc/konductor/pki/hypervisor/ca.crt" ]; then
          openssl x509 -in "/etc/konductor/pki/hypervisor/ca.crt" -noout -subject -issuer -dates -fingerprint
        else
          echo "Not mounted"
        fi
      }
    '';
  };
}
