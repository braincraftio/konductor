# src/modules/ghostty-web.nix
# NixOS module for Ghostty Web Terminal service
#
# Self-contained module providing:
# - Systemd service (disabled by default)
# - Firewall integration
# - Cloud-init activation support
#
# Enable via cloud-init:
#   runcmd:
#     - systemctl enable --now ghostty-web

{ config, lib, pkgs, ... }:

let
  cfg = config.services.ghostty-web;

  # Import the ghostty-web package
  ghosttyWeb = import ../programs/ghostty-web { inherit pkgs lib; };

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
      default = 7681;
      description = "TCP port for HTTP and WebSocket server.";
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

      after = [ "network.target" ];
      wants = [ "network.target" ];

      # IMPORTANT: Empty wantedBy means service does NOT start at boot.
      # Enable via cloud-init or manually: systemctl enable --now ghostty-web
      wantedBy = [ ];

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

        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/ghostty-web-server"
          "--port" (toString cfg.port)
          "--host" cfg.host
          "--working-directory" (toString cfg.workingDirectory)
          "--max-sessions" (toString cfg.maxSessions)
          "--idle-timeout" (toString cfg.idleTimeout)
        ];

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
