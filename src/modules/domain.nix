# src/modules/domain.nix
# FreeIPA domain integration module for Konductor VMs
#
# Deploy-time optional: if cloud-init writes /etc/konductor/domain.env
# the VM joins the FreeIPA domain at first boot. Without this file,
# all domain services are inert and the VM operates standalone.
#
# Zero deployment-specific strings in the Nix store.
#
# Systemd DAG:
#
#   cloud-init writes /etc/konductor/domain.env
#       │
#       ▼
#   konductor-domain-config.service
#       │ ConditionPathExists=/etc/konductor/domain.env
#       │ Writes: krb5.conf, ipa/default.conf, ca.crt, auto.nfshome, idmapd
#       │ Does NOT write sssd.conf (sssd owns that via its preStart)
#       │ Does NOT have Before=sssd (no ordering dependency)
#       │
#       ▼
#   konductor-domain-join.service
#       │ ConditionPathExists=/etc/konductor/domain.env
#       │ ConditionPathExists=!/etc/krb5.keytab
#       │ Before=sssd.service (sssd waits for keytab)
#       │ Runs ipa-join → creates /etc/krb5.keytab
#       │ Does NOT restart sssd (Before= ordering handles it)
#       │
#       ▼
#   sssd.service
#       │ After=konductor-domain-join.service
#       │ ExecStartPre OVERRIDDEN: checks domain.env + keytab
#       │   Both exist → writes IPA sssd.conf
#       │   Otherwise  → writes standalone sssd.conf (no domain)
#       │ Never crashes, never blocks boot
#       │
#       ▼
#   autofs.service (After=sssd, built-in)
#   rpc-gssd (ConditionPathExists=/etc/krb5.keytab)
#
# Standalone boot (no domain.env):
#   domain-config SKIPPED, domain-join SKIPPED
#   sssd preStart writes standalone config → sssd starts, nss/pam work
#
# Domain boot (domain.env exists, first boot):
#   domain-config writes krb5/ipa configs
#   domain-join runs ipa-join → keytab created
#   sssd preStart sees domain.env + keytab → writes IPA config
#   sssd starts with IPA provider → domain users resolve
#
# Subsequent domain boot (keytab persists):
#   domain-config re-generates overlay configs
#   domain-join SKIPPED (keytab exists)
#   sssd preStart writes IPA config → sssd starts

{
  lib,
  pkgs,
  ...
}:

let
  domainEnv = "/etc/konductor/domain.env";
  caCertPath = "/etc/konductor/ipa/ca.crt";

  # sssd preStart: the SOLE writer of /var/lib/sssd/sssd.conf.
  # Checks domain.env + keytab to decide between IPA and standalone config.
  # Replaces the NixOS sssd module's envsubst-based preStart entirely.
  sssdPreStart = pkgs.writeShellScript "sssd-domain-aware-pre-start" ''
        set -euo pipefail

        SSSD_CONF="/var/lib/sssd/sssd.conf"

        # Create required SSSD directories
        mkdir -p /var/lib/sssd/conf.d
        mkdir -p /var/lib/sss/{pubconf,db,mc,pipes,gpo_cache,secrets}
        mkdir -p /var/lib/sss/pipes/private
        mkdir -p /var/lib/sss/pubconf/krb5.include.d

        # Remove stale config
        [ -f "$SSSD_CONF" ] && rm -f "$SSSD_CONF"

        old_umask=$(umask)
        umask 0177

        if [ -f "${domainEnv}" ] && [ -f "/etc/krb5.keytab" ]; then
          # Domain-joined: write IPA provider config
          # Source domain.env for variable values
          set -a
          . "${domainEnv}"
          set +a

          IPA_FQDN="$(cat /etc/hostname).$IPA_DOMAIN"

          cat > "$SSSD_CONF" <<SSSDEOF
    [sssd]
    services = nss, pam, ssh, sudo, autofs, ifp
    domains = $IPA_DOMAIN

    [domain/$IPA_DOMAIN]
    id_provider = ipa
    auth_provider = ipa
    access_provider = ipa
    chpass_provider = ipa
    ipa_domain = $IPA_DOMAIN
    ipa_server = _srv_, $IPA_SERVER
    ipa_hostname = $IPA_FQDN
    krb5_realm = $IPA_REALM
    cache_credentials = True
    krb5_store_password_if_offline = True
    ldap_tls_cacert = /etc/ipa/ca.crt
    dyndns_update = True
    dyndns_iface = !docker*,!podman*,!veth*,!br-*,!kube-*,!cali*,!tunl*,!vxlan*,*
    autofs_provider = ipa
    ipa_automount_location = default
    fallback_homedir = /nfshome/%u

    [nss]
    homedir_substring = /nfshome

    [pam]
    pam_pwd_expiration_warning = 3
    pam_verbosity = 3

    [ssh]

    [sudo]

    [autofs]

    [ifp]
    allowed_uids = root
    SSSDEOF
          echo "sssd-pre-start: wrote IPA config for domain $IPA_DOMAIN"
        else
          # Standalone: minimal config, no domain, no crash
          cat > "$SSSD_CONF" <<SSSDEOF
    [sssd]
    services = nss, pam

    [nss]

    [pam]
    SSSDEOF
          echo "sssd-pre-start: wrote standalone config (no domain)"
        fi

        umask $old_umask
  '';

  # Script: write domain config files (everything EXCEPT sssd.conf)
  domainConfigScript = pkgs.writeShellScript "konductor-domain-config" ''
        set -euo pipefail

        echo "═══════════════════════════════════════════════════"
        echo "  Konductor Domain Configuration"
        echo "═══════════════════════════════════════════════════"

        # Validate required variables (sourced via EnvironmentFile)
        for var in IPA_SERVER IPA_REALM IPA_DOMAIN IPA_BASEDN; do
          if [ -z "''${!var:-}" ]; then
            echo "ERROR: $var not set in ${domainEnv}"
            exit 1
          fi
        done

        IPA_FQDN="$(hostname).$IPA_DOMAIN"

        # Fetch IPA CA cert from server over HTTP (same as ipa-client-install).
        if [ ! -f "${caCertPath}" ]; then
          echo "  Fetching CA cert from http://$IPA_SERVER/ipa/config/ca.crt..."
          mkdir -p "$(dirname "${caCertPath}")"
          if ! curl -fsSL -o "${caCertPath}" "http://$IPA_SERVER/ipa/config/ca.crt"; then
            echo "ERROR: Failed to fetch IPA CA cert from $IPA_SERVER"
            exit 1
          fi
          echo "  ✓ CA cert fetched"
        else
          echo "  ✓ CA cert exists (cloud-init or previous boot)"
        fi

        echo "  Server:   $IPA_SERVER"
        echo "  Realm:    $IPA_REALM"
        echo "  Domain:   $IPA_DOMAIN"
        echo "  Hostname: $IPA_FQDN"

        # --- /etc/krb5.conf ---
        echo "  Writing /etc/krb5.conf..."
        cat > /etc/krb5.conf <<KRBEOF
    [libdefaults]
      default_realm = $IPA_REALM
      dns_lookup_realm = false
      dns_lookup_kdc = true
      dns_canonicalize_hostname = false
      rdns = false
      ticket_lifetime = 24h
      forwardable = true
      udp_preference_limit = 0
      default_ccache_name = KEYRING:persistent:%{uid}

    [realms]
      $IPA_REALM = {
        kdc = $IPA_SERVER:88
        master_kdc = $IPA_SERVER:88
        admin_server = $IPA_SERVER:749
        default_domain = $IPA_DOMAIN
        pkinit_anchors = FILE:/etc/ipa/ca.crt
      }

    [domain_realm]
      .$IPA_DOMAIN = $IPA_REALM
      $IPA_DOMAIN = $IPA_REALM
      $IPA_SERVER = $IPA_REALM
    KRBEOF

        # --- /etc/ipa/default.conf ---
        echo "  Writing /etc/ipa/default.conf..."
        mkdir -p /etc/ipa
        cat > /etc/ipa/default.conf <<IPAEOF
    [global]
    basedn = $IPA_BASEDN
    realm = $IPA_REALM
    domain = $IPA_DOMAIN
    server = $IPA_SERVER
    host = $IPA_FQDN
    xmlrpc_uri = https://$IPA_SERVER/ipa/xml
    enable_ra = True
    IPAEOF

        # --- /etc/ipa/ca.crt ---
        cp "${caCertPath}" /etc/ipa/ca.crt

        # --- /etc/konductor/auto.nfshome ---
        if [ -n "''${NFS_HOME_SERVER:-}" ]; then
          echo "  Writing autofs NFS home map..."
          mkdir -p /etc/konductor
          cat > /etc/konductor/auto.nfshome <<NFSEOF
    * -fstype=nfs4,sec=krb5p,rw,hard,vers=4.2 $NFS_HOME_SERVER:/srv/nfshome/&
    NFSEOF
        fi

        # --- /etc/idmapd.conf Domain ---
        if [ -f /etc/idmapd.conf ]; then
          sed -i "s/^.*Domain = .*/Domain = $IPA_DOMAIN/" /etc/idmapd.conf
        fi

        echo "  ✓ Domain configuration complete"
        echo "═══════════════════════════════════════════════════"
  '';

  # Script: obtain keytab via ipa-join (run-once)
  domainJoinScript = pkgs.writeShellScript "konductor-domain-join" ''
    set -euo pipefail

    echo "═══════════════════════════════════════════════════"
    echo "  Konductor FreeIPA Domain Join"
    echo "═══════════════════════════════════════════════════"

    IPA_FQDN="$(hostname).$IPA_DOMAIN"

    if [ -z "''${IPA_OTP:-}" ]; then
      echo "ERROR: IPA_OTP not set in ${domainEnv}"
      exit 1
    fi

    echo "  Joining $IPA_FQDN to $IPA_REALM with OTP..."
    rc=0
    ipa-join \
      -s "$IPA_SERVER" \
      -h "$IPA_FQDN" \
      -k /etc/krb5.keytab \
      -w "$IPA_OTP" \
      -b "$IPA_BASEDN" \
      -f || rc=$?

    if [ "$rc" -ne 0 ] && [ "$rc" -ne 13 ]; then
      echo "ERROR: ipa-join failed with exit code $rc"
      echo "  15 = incorrect OTP | 16 = not FQDN | 14 = LDAP failure"
      exit "$rc"
    fi

    if [ "$rc" -eq 13 ]; then
      echo "  Host already enrolled (exit 13) — keytab should exist"
    fi

    chmod 600 /etc/krb5.keytab
    echo "  ✓ Keytab obtained: /etc/krb5.keytab"
    echo "═══════════════════════════════════════════════════"
  '';

in
{
  # =========================================================================
  # NFS4 client — activates rpc-gssd (gated on /etc/krb5.keytab)
  # =========================================================================
  boot.supportedFilesystems = [ "nfs4" ];

  # =========================================================================
  # SSSD — ExecStartPre overridden to be domain-aware.
  # The baked-in config value is unused — our preStart writes sssd.conf
  # based on runtime state (domain.env + keytab presence).
  # services.sssd.config must be set to satisfy the module's assertion
  # (config and settings are mutually exclusive, one must be non-empty).
  # =========================================================================
  services.sssd = {
    enable = true;
    sshAuthorizedKeysIntegration = true;
    config = ''
      [sssd]
      services = nss, pam

      [nss]

      [pam]
    '';
  };

  # Override sssd's ExecStartPre with our domain-aware preStart.
  # This is the SOLE writer of /var/lib/sssd/sssd.conf.
  # Checks domain.env + keytab → IPA config or standalone config.
  # Never crashes, never blocks boot.
  systemd.services.sssd.serviceConfig.ExecStartPre = lib.mkForce sssdPreStart;

  # =========================================================================
  # Autofs — NFS home directories (inert without map file)
  # =========================================================================
  services.autofs = {
    enable = true;
    timeout = 600;
    autoMaster = ''
      /nfshome  file:/etc/konductor/auto.nfshome
    '';
  };

  # =========================================================================
  # nsswitch automount for SSSD-served IPA automount maps
  # =========================================================================
  environment.etc."nsswitch.conf".text = lib.mkAfter "\nautomount: sss files\n";

  # =========================================================================
  # PAM: create home directory on first login (NFS fallback safety net)
  # =========================================================================
  security.pam.services.sshd.makeHomeDir = true;

  # =========================================================================
  # /nfshome mountpoint for autofs
  # =========================================================================
  systemd.tmpfiles.rules = [ "d /nfshome 0755 root root -" ];

  # =========================================================================
  # FreeIPA shell symlinks — canonical NixOS IPA pattern
  # (nixos/modules/security/ipa.nix lines 317-325)
  #
  # FreeIPA sets user loginShell to /bin/bash (POSIX convention).
  # NixOS has no /bin/bash — bash lives in /nix/store. sshd checks
  # shell existence before allowing login, rejecting domain users
  # with "shell /bin/bash does not exist".
  #
  # Create /bin/bash symlink via tmpfiles (same mechanism as the
  # upstream NixOS security.ipa module).
  # =========================================================================
  systemd.tmpfiles.settings."10-ipa-shells" = lib.foldl' (
    acc: pkg:
    (
      acc
      // {
        ${pkg.shellPath}."L+".argument = "${pkg}${pkg.shellPath}";
      }
    )
  ) { } [ pkgs.bash ];

  # =========================================================================
  # Packages for domain operations
  # =========================================================================
  environment.systemPackages = with pkgs; [
    freeipa
    krb5
  ];

  # =========================================================================
  # Domain services
  # =========================================================================
  systemd.services = {
    # Phase 1: Write domain config files (everything except sssd.conf)
    # No Before=sssd — sssd does not depend on this service.
    # sssd's own preStart reads domain.env directly.
    konductor-domain-config = {
      description = "Generate FreeIPA domain configuration";
      after = [
        "cloud-init.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      before = [ "konductor-domain-join.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = domainEnv;
      path = with pkgs; [
        coreutils
        gnused
        hostname
        curl
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = domainEnv;
        ExecStart = domainConfigScript;
      };
    };

    # Phase 2: Obtain keytab via ipa-join (run-once)
    # Before=sssd — sssd waits for keytab before starting.
    # Does NOT restart sssd — Before= ordering handles it.
    konductor-domain-join = {
      description = "Join Konductor VM to FreeIPA domain";
      after = [
        "konductor-domain-config.service"
        "network-online.target"
      ];
      wants = [
        "network-online.target"
        "konductor-domain-config.service"
      ];
      before = [ "sssd.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = [
        domainEnv
        "!/etc/krb5.keytab"
      ];
      path = with pkgs; [
        freeipa
        krb5
        coreutils
        hostname
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = domainEnv;
        ExecStart = domainJoinScript;
      };
    };
  };

  # Order sssd after domain-join so keytab exists before sssd starts
  systemd.services.sssd.after = lib.mkAfter [
    "konductor-domain-join.service"
  ];
}
