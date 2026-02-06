# src/modules/ghostty-web.nix
# NixOS module for Ghostty Web Terminal service
#
# Features:
# - Systemd service (disabled by default)
# - Firewall integration
# - SSL/TLS support (PKI integration)
# - Reverse proxy support (basePath)
# - WebSocket origin checking
# - Cloud-init activation support
# - Catppuccin Frappé theme (matches tmux/neovim/ttyd)
# - Build-time font embedding (airgap-safe)
#
# Enable via cloud-init:
#   runcmd:
#     - systemctl enable --now ghostty-web
#
# Or imperatively:
#   sudo systemctl enable --now ghostty-web

{ config, lib, pkgs, ... }:

let
  cfg = config.services.ghostty-web;

  # Import ghostty-web program module (includes theme and defaults)
  ghosttyWeb = import ../programs/ghostty-web { inherit pkgs lib; };

  # Theme JSON for reference (theme is embedded in index.html)
  themeJson = builtins.toJSON ghosttyWeb.theme;

in
{
  # ===========================================================================
  # MODULE OPTIONS
  # ===========================================================================

  options.services.ghostty-web = {
    enable = lib.mkEnableOption "Ghostty web terminal service";

    package = lib.mkOption {
      type = lib.types.package;
      default = ghosttyWeb.server;
      defaultText = lib.literalExpression "ghostty-web-server";
      description = "The ghostty-web server package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7682;
      description = "TCP port for HTTP and WebSocket server (default 7682 to avoid ttyd conflict on 7681).";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host address to bind to.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "kc2";
      description = "User account for service execution and PTY sessions.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for service execution.";
    };

    shell = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Shell for PTY sessions.
        If null, uses the user's SHELL environment variable or /bin/bash.
      '';
    };

    workingDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/workspace";
      description = "Initial working directory for PTY sessions.";
    };

    maxSessions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Maximum number of concurrent PTY sessions.";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1800;
      description = ''
        Idle session timeout in seconds.
        Sessions with no activity will be terminated after this duration.
        Set to 0 to disable idle timeout.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall port for ghostty-web.";
    };

    # -------------------------------------------------------------------------
    # SSL OPTIONS (matches ttyd module)
    # -------------------------------------------------------------------------
    enableSSL = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable SSL/TLS using VM's wildcard certificate.
        Requires konductor.pki module (generates certs on boot).
        Certificate paths: /etc/konductor/pki/vm/wildcard.{crt,key}
      '';
    };

    sslCertPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/konductor/pki/vm/wildcard.crt";
      description = "Path to SSL certificate (PEM format).";
    };

    sslKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/konductor/pki/vm/wildcard.key";
      description = "Path to SSL private key (PEM format).";
    };

    # -------------------------------------------------------------------------
    # REVERSE PROXY OPTIONS
    # -------------------------------------------------------------------------
    basePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/terminal";
      description = ''
        Base path for requests from reverse proxy.
        Set when running behind Envoy Gateway or similar.
        Example: /terminal makes the app accessible at https://host/terminal
      '';
    };

    # -------------------------------------------------------------------------
    # SECURITY OPTIONS
    # -------------------------------------------------------------------------
    checkOrigin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Reject WebSocket connections from different origins.
        Enable when exposed to untrusted networks.
        Protects against cross-site WebSocket hijacking.
      '';
    };
  };

  # ===========================================================================
  # MODULE IMPLEMENTATION
  # ===========================================================================

  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # SYSTEMD SERVICE
    # -------------------------------------------------------------------------
    systemd.services.ghostty-web = {
      description = "Ghostty Web Terminal Service";
      documentation = [ "https://github.com/coder/ghostty-web" ];

      after = [ "network.target" ] ++ lib.optional cfg.enableSSL "konductor.service";
      wants = [ "network.target" ];
      requires = lib.optional cfg.enableSSL "konductor.service";

      # IMPORTANT: Empty wantedBy means service does NOT start at boot.
      # Enable via cloud-init or manually: systemctl enable --now ghostty-web
      wantedBy = [ ];

      # Wait for SSL certificates to exist before starting (when SSL enabled)
      unitConfig = lib.mkIf cfg.enableSSL {
        ConditionPathExists = [
          cfg.sslCertPath
          cfg.sslKeyPath
        ];
      };

      environment = {
        NODE_ENV = "production";
        HOME = "/home/${cfg.user}";
        LANG = "C.UTF-8";
      } // lib.optionalAttrs (cfg.shell != null) {
        SHELL = toString cfg.shell;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart =
          let
            # SSL flags (when enabled)
            sslFlags = lib.optionals cfg.enableSSL [
              "--ssl"
              "--ssl-cert" cfg.sslCertPath
              "--ssl-key" cfg.sslKeyPath
            ];

            # Optional flags
            optionalFlags = lib.optional (cfg.basePath != null) "--base-path ${cfg.basePath}"
              ++ lib.optional cfg.checkOrigin "--check-origin";
          in
          lib.concatStringsSep " " ([
            "${cfg.package}/bin/ghostty-web-server"
            "--port" (toString cfg.port)
            "--host" cfg.host
            "--working-directory" (toString cfg.workingDirectory)
            "--max-sessions" (toString cfg.maxSessions)
            "--idle-timeout" (toString cfg.idleTimeout)
          ] ++ sslFlags ++ optionalFlags);

        Restart = "always";
        RestartSec = 5;

        # -------------------------------------------------------------------
        # SECURITY HARDENING
        # -------------------------------------------------------------------
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          cfg.workingDirectory
          "/home/${cfg.user}"
        ];
        # Allow reading SSL certificates (when SSL enabled)
        ReadOnlyPaths = lib.mkIf cfg.enableSSL [
          (builtins.dirOf cfg.sslCertPath)
        ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = false; # Required for WASM

        # -------------------------------------------------------------------
        # RESOURCE LIMITS
        # -------------------------------------------------------------------
        MemoryMax = "512M";
        TasksMax = toString (cfg.maxSessions * 2 + 10);
      };
    };

    # -------------------------------------------------------------------------
    # FIREWALL
    # -------------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
