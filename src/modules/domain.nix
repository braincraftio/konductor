# src/modules/domain.nix
# FreeIPA domain integration module for Konductor VMs
#
# Deploy-time optional: if cloud-init writes /etc/konductor/domain.env
# and /etc/konductor/ipa/ca.crt, the VM joins the FreeIPA domain at
# first boot. Without these files, all domain services are inert and
# the VM operates standalone with local users only.
#
# Zero deployment-specific strings are baked into the Nix store.
# All domain config (server, realm, OTP, NFS server) comes from
# /etc/konductor/domain.env at runtime.
#
# Enrollment method: ipa-join with OTP (Path 1 from enrollment analysis)
#   - Server-side: ipa host-add <fqdn> --random --force → OTP
#   - Client-side: ipa-join -s <server> -h <fqdn> -w <OTP> -f -b <basedn>
#   - ipa-join triggers ipa_enrollment.c extended operation (sets krbPrincipalName)
#   - ipa-join internally calls ipa-getkeytab (retrieves keytab, consumes OTP)
#   - OTP is single-use: self-destructs after consumption (security)
#
# Exit codes (from ipa-join.1):
#   0  = success
#   13 = host already enrolled (krbLastPwdChange set)
#   15 = incorrect bulk password (OTP wrong or consumed)
#   16 = hostname not FQDN
#
# Boot sequence (domain-joined):
#   cloud-init writes domain.env + ca.crt
#     → konductor-domain-config.service generates krb5.conf, sssd.conf,
#       ipa/default.conf, auto.nfshome, idmapd domain
#     → konductor-domain-join.service runs ipa-join with OTP → keytab
#     → sssd.service restarts with IPA config → domain user resolution
#     → autofs.service restarts → NFS home directories mount on access
#     → rpc-gssd starts (ConditionPathExists /etc/krb5.keytab satisfied)
#     → SSH accepts domain users via sss_ssh_authorizedkeys
#
# Boot sequence (standalone):
#   no domain.env → all Condition gates false → sssd runs files-only
#   → local users (kc2, kc2admin, runner, forgejo) work normally
#
# Cloud-init write_files (Pulumi-generated):
#   /etc/konductor/domain.env:
#     IPA_SERVER=west01.idm.braincraft.io
#     IPA_REALM=IDM.BRAINCRAFT.IO
#     IPA_DOMAIN=idm.braincraft.io
#     IPA_BASEDN=dc=idm,dc=braincraft,dc=io
#     IPA_OTP=<from-ipa-host-add-random>
#     NFS_HOME_SERVER=home.idm.braincraft.io
#   /etc/konductor/ipa/ca.crt:
#     <FreeIPA Dogtag CA certificate PEM>
#
# Lifecycle (Pulumi-managed):
#   Create: host_add(fqdn, random=True, force=True) → OTP → cloud-init → VM boots → ipa-join
#   Destroy: host_del(fqdn) → cascades service principals → clean IPA state
#   Re-deploy: host_del + host_add --random → fresh OTP → new VM joins clean

{
  lib,
  pkgs,
  ...
}:

let
  domainEnv = "/etc/konductor/domain.env";
  caCertPath = "/etc/konductor/ipa/ca.crt";

  # Script: write all domain config files (overlay-writable /etc + /var/lib)
  # Runs on every boot when domain.env exists (idempotent config generation).
  # Does NOT run ipa-join — that is a separate run-once service.
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
        # http://<server>/ipa/config/ca.crt is unauthenticated — this is the
        # standard bootstrap path. The cert is then used for all subsequent
        # TLS connections (LDAP, JSON-RPC, ipa-join).
        if [ ! -f "${caCertPath}" ]; then
          echo "  Fetching CA cert from http://$IPA_SERVER/ipa/config/ca.crt..."
          mkdir -p "$(dirname "${caCertPath}")"
          if ! curl -fsSL -o "${caCertPath}" "http://$IPA_SERVER/ipa/config/ca.crt"; then
            echo "ERROR: Failed to fetch IPA CA cert from $IPA_SERVER"
            echo "  Ensure the IPA server is reachable over HTTP"
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

        # --- /etc/krb5.conf (overlay writable) ---
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

        # --- /etc/ipa/ca.crt (libcurl needs a real file, not symlink) ---
        cp "${caCertPath}" /etc/ipa/ca.crt

        # --- /var/lib/sssd/sssd.conf (mutable, NixOS sssd reads from here) ---
        echo "  Writing /var/lib/sssd/sssd.conf..."
        mkdir -p /var/lib/sssd
        old_umask=$(umask)
        umask 0177
        cat > /var/lib/sssd/sssd.conf <<SSSDEOF
    [sssd]
    config_file_version = 2
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
        umask $old_umask

        # --- /etc/konductor/auto.nfshome (autofs map for NFS homes) ---
        if [ -n "''${NFS_HOME_SERVER:-}" ]; then
          echo "  Writing autofs NFS home map..."
          mkdir -p /etc/konductor
          cat > /etc/konductor/auto.nfshome <<NFSEOF
    * -fstype=nfs4,sec=krb5p,rw,hard,vers=4.2 $NFS_HOME_SERVER:/srv/nfshome/&
    NFSEOF
        fi

        # --- /etc/idmapd.conf Domain (overlay writable) ---
        if [ -f /etc/idmapd.conf ]; then
          sed -i "s/^.*Domain = .*/Domain = $IPA_DOMAIN/" /etc/idmapd.conf
        fi

        echo "  ✓ Domain configuration complete"
        echo "═══════════════════════════════════════════════════"
  '';

  # Script: obtain keytab via ipa-join (run-once, OTP is single-use)
  #
  # ipa-join flags (from ipa-join.1):
  #   -s  IPA server FQDN (required, no /etc/ipa/default.conf exists yet)
  #   -h  hostname FQDN (required for correct principal name)
  #   -k  keytab output path (default /etc/krb5.keytab)
  #   -w  OTP/bulk password (authenticates via LDAP simple bind)
  #   -b  basedn (required with -w when anonymous binds disallowed)
  #   -f  force enroll even if host entry already exists
  #
  # ipa-join internally:
  #   1. LDAP bind as host DN using OTP (-w)
  #   2. Triggers ipa_enrollment.c extended operation (OID 2.16.840.1.113730.3.8.10.3)
  #   3. Server sets krbPrincipalName = host/<fqdn>@REALM if not present
  #   4. Forks ipa-getkeytab to retrieve keytab (consumes OTP, sets krbPrincipalKey)
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

    # Exit 13 = host already enrolled (krbLastPwdChange set in ipa_enrollment.c)
    # Treat as success — keytab should already exist from prior enrollment
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 13 ]; then
      echo "ERROR: ipa-join failed with exit code $rc"
      echo "  Common causes:"
      echo "    15 = incorrect OTP (wrong or already consumed)"
      echo "    16 = hostname not fully-qualified"
      echo "    14 = LDAP connection failure (check CA cert, network)"
      exit "$rc"
    fi

    if [ "$rc" -eq 13 ]; then
      echo "  Host already enrolled (exit 13) — keytab should exist"
    fi

    chmod 600 /etc/krb5.keytab
    echo "  ✓ Keytab obtained: /etc/krb5.keytab"

    # Restart services that depend on domain config + keytab
    echo "  Restarting SSSD..."
    systemctl restart sssd.service || echo "  WARNING: sssd restart failed"
    echo "  Restarting autofs..."
    systemctl restart autofs.service || echo "  WARNING: autofs restart failed"

    echo "═══════════════════════════════════════════════════"
    echo "  ✓ Domain join complete: $IPA_FQDN"
    echo "═══════════════════════════════════════════════════"
  '';

in
{
  # =========================================================================
  # NFS4 client support — activates nfs-utils, rpcbind, rpc-gssd, idmapd
  # rpc-gssd and auth-rpcgss-module both gate on /etc/krb5.keytab via
  # ConditionPathExists (nfs.nix lines 192-205) — start automatically
  # once ipa-join creates the keytab
  # =========================================================================
  boot.supportedFilesystems = [ "nfs4" ];

  # =========================================================================
  # SSSD — files-only fallback for standalone, IPA-backed after domain join
  # The NixOS sssd module writes config to /var/lib/sssd/sssd.conf (mutable)
  # and runs envsubst in preStart. konductor-domain-config overwrites
  # /var/lib/sssd/sssd.conf directly with the IPA config.
  # =========================================================================
  services.sssd = {
    enable = true;
    sshAuthorizedKeysIntegration = true;
    # Freeform config — files-only fallback for standalone VMs.
    # konductor-domain-config overwrites /var/lib/sssd/sssd.conf
    # with the IPA-specific config at first boot.
    config = ''
      [sssd]
      config_file_version = 2
      services = nss, pam
      domains = LOCAL
      [domain/LOCAL]
      id_provider = files
      [nss]
      [pam]
    '';
  };

  # =========================================================================
  # Autofs — NFS home directories (inert without map file)
  # Map file /etc/konductor/auto.nfshome written by domain-config service.
  # autofs module has after = [ "sssd.service" ] built-in (autofs.nix line 85).
  # autoMaster becomes a store path via pkgs.writeText; the store file
  # references the mutable /etc/konductor/auto.nfshome path.
  # =========================================================================
  services.autofs = {
    enable = true;
    timeout = 600;
    autoMaster = ''
      /nfshome  file:/etc/konductor/auto.nfshome
    '';
  };

  # =========================================================================
  # nsswitch: add automount database for SSSD-served IPA automount maps
  # system.nssDatabases has no automount option (only passwd, group, shadow,
  # sudoers, hosts, services, subuid, subgid — nsswitch.nix lines 28-124).
  # Append to the generated nsswitch.conf.
  # =========================================================================
  environment.etc."nsswitch.conf".text = lib.mkAfter "\nautomount: sss files\n";

  # =========================================================================
  # PAM: create home directory on first login (safety net for NFS failure)
  # Uses pam_mkhomedir.so from pkgs.pam (not oddjob — NixOS doesn't use it)
  # =========================================================================
  security.pam.services.sshd.makeHomeDir = true;

  # =========================================================================
  # /nfshome mountpoint for autofs
  # =========================================================================
  systemd.tmpfiles.rules = [ "d /nfshome 0755 root root -" ];

  # =========================================================================
  # Packages needed for domain operations
  # nfs-utils is NOT listed here — boot.supportedFilesystems = ["nfs4"]
  # pulls it in via system.fsPackages (nfs.nix line 150)
  # =========================================================================
  environment.systemPackages = with pkgs; [
    freeipa # ipa-join, ipa-getkeytab, ipa CLI
    krb5 # kinit, klist, kdestroy
  ];

  # =========================================================================
  # Domain services — two-phase: config (every boot) + join (run-once)
  # =========================================================================
  systemd.services = {
    # Phase 1: Write all domain config files (idempotent, every boot)
    # Runs whenever domain.env exists, regardless of keytab state.
    # This handles nixos-rebuild recovery: overlay is cleared on rebuild
    # so krb5.conf/sssd.conf/ipa config are lost, but the keytab persists
    # (it's a plain file at /etc/krb5.keytab, not an overlay symlink).
    # This service re-generates all config files from domain.env.
    konductor-domain-config = {
      description = "Generate FreeIPA domain configuration";
      after = [
        "cloud-init.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      before = [
        "sssd.service"
        "autofs.service"
        "konductor-domain-join.service"
      ];
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

    # Phase 2: Obtain keytab via ipa-join (run-once, OTP is single-use)
    # Gated on: domain.env exists AND keytab does NOT exist.
    # After config phase writes krb5.conf + ipa/default.conf.
    # Once keytab exists, this service never runs again (idempotent).
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
      before = [
        "sssd.service"
        "autofs.service"
      ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = [
        domainEnv
        "!/etc/krb5.keytab"
      ];
      path = with pkgs; [
        freeipa
        krb5
        coreutils
        systemd
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

  # Order sssd after both domain services so it picks up IPA config
  systemd.services.sssd.after = lib.mkAfter [
    "konductor-domain-config.service"
    "konductor-domain-join.service"
  ];
}
