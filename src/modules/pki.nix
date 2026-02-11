# src/modules/pki.nix
# Konductor PKI - VM identity and certificate chain of trust
#
# Uses the Python PKI package (src/pki/) with the cryptography library
# to generate X.509 certificates with P-384 CA keys and P-256 leaf keys.
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

  # Python with cryptography for X.509 cert generation
  pythonWithCrypto = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
  pythonPki = "${pythonWithCrypto}/bin/python3";

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
      description = "Key algorithm: ec (P-384 CA, P-256 leaf) or rsa (4096-bit)";
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
    # Keep openssl for manual debugging; cryptography comes via languages.nix
    environment.systemPackages = [ pkgs.openssl ];

    # Create PKI directory structure
    systemd.tmpfiles.rules = [
      "d /etc/konductor/pki 0755 root root -"
      "d /etc/konductor/pki/vm 0755 root root -"
      "d /etc/konductor/pki/hypervisor 0755 root root -"
      "d /etc/konductor/pki/bundle 0755 root root -"
    ];

    systemd.services = {
      # =====================================================================
      # VM-local CA Generation
      # =====================================================================
      # Generates self-signed CA and wildcard certificate on first boot.
      # Uses Python PKI package with cryptography library.
      # Idempotent: only runs if ca.crt doesn't exist.
      konductor-pki-vm = {
        description = "Generate Konductor VM-local PKI";
        after = [ "local-fs.target" ];
        before = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        unitConfig = {
          ConditionPathExists = "!/etc/konductor/pki/vm/ca.crt";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = [
            "PYTHONPATH=/opt/konductor/src/src"
          ];
          ExecStart = pkgs.writeShellScript "generate-vm-pki" ''
            set -euo pipefail

            echo "Generating Konductor VM PKI via python3 -m pki generate"

            ${pythonPki} -m pki generate \
              --domain "${cfg.domain}" \
              --org "${cfg.organization}" \
              --ou "${cfg.organizationalUnit}" \
              --ca-days ${toString cfg.caValidityDays} \
              --cert-days ${toString cfg.certValidityDays}

            echo "VM PKI generation complete"

            # Output status to serial console for build attestation
            ${pythonPki} -m pki status | tee /dev/ttyS0 2>/dev/null || true
          '';
        };
      };

      # =====================================================================
      # Hypervisor CA Import (if mounted)
      # =====================================================================
      # Imports hypervisor CA from mount point using Python PKI package.
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
          Environment = [
            "PYTHONPATH=/opt/konductor/src/src"
          ];
          ExecStart = pkgs.writeShellScript "import-hypervisor-pki" ''
            set -euo pipefail

            echo "Importing hypervisor CA via python3 -m pki hypervisor"

            ${pythonPki} -m pki hypervisor \
              --ca "${toString cfg.hypervisorCaPath}" \
              ${lib.optionalString (cfg.hypervisorKeyPath != null)
                "--key \"${toString cfg.hypervisorKeyPath}\""
              }

            echo "Hypervisor CA import complete"

            # Output status to serial console for build attestation
            ${pythonPki} -m pki status | tee /dev/ttyS0 2>/dev/null || true
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
          Environment = [
            "PYTHONPATH=/opt/konductor/src/src"
          ];
          ExecStart = pkgs.writeShellScript "generate-ca-bundle" ''
            set -euo pipefail

            echo "Generating Konductor CA bundle via python3 -m pki bundle"

            ${pythonPki} -m pki bundle

            echo "CA bundle generation complete"
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

      konductor-ca-status() {
        PYTHONPATH=/opt/konductor/src/src python3 -m pki status
      }
    '';
  };
}
