# src/modules/ttyd.nix
# NixOS module for Konductor ttyd Web Terminal service
#
# Named konductor-ttyd to avoid conflict with nixpkgs' services.ttyd module.
# This module provides Konductor-specific defaults:
# - Catppuccin Frappé theme
# - Embedded Nerd Fonts (via overlay)
# - Systemd service (disabled by default)
# - Firewall integration
# - Cloud-init activation support
#
# Enable via cloud-init:
#   runcmd:
#     - systemctl enable --now konductor-ttyd
#
# Or imperatively:
#   sudo systemctl enable --now konductor-ttyd

{ config, lib, pkgs, ... }:

let
  cfg = config.services.konductor-ttyd;

  # Import theme from ttyd program module
  ttydProgram = import ../programs/ttyd { inherit pkgs lib; };
  themeJson = builtins.toJSON ttydProgram.theme;

in
{
  # ===========================================================================
  # MODULE OPTIONS
  # ===========================================================================

  options.services.konductor-ttyd = {
    enable = lib.mkEnableOption "Konductor ttyd web terminal service (themed)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ttyd;
      defaultText = lib.literalExpression "pkgs.ttyd";
      description = ''
        The ttyd package to use.
        By default uses the Konductor-patched ttyd with embedded Nerd Fonts
        (via src/overlays/ttyd.nix).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7681;
      description = "TCP port for HTTP and WebSocket server.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Network interface or IP address to bind to.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "kc2";
      description = "User account for service execution and shell sessions.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for service execution.";
    };

    shell = lib.mkOption {
      type = lib.types.str;
      default = "/bin/bash";
      description = "Shell to spawn for terminal sessions.";
    };

    shellArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "-l" ];
      description = "Arguments to pass to the shell (e.g., -l for login shell).";
    };

    workingDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/workspace";
      description = "Initial working directory for shell sessions.";
    };

    maxClients = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10;
      description = ''
        Maximum number of concurrent clients.
        Set to 0 for unlimited.
      '';
    };

    terminalType = lib.mkOption {
      type = lib.types.str;
      default = "xterm-256color";
      description = "Terminal type to report (TERM environment variable).";
    };

    enableIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IPv6 support.";
    };

    checkOrigin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reject WebSocket connections from different origins.";
    };

    basePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/terminal";
      description = ''
        Base path for requests from reverse proxy.
        Set when running behind Envoy Gateway or similar.
      '';
    };

    clientOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { fontSize = "16"; };
      description = ''
        Additional xterm.js client options passed via -t flag.
        Theme and font options are set automatically.
      '';
    };

    enableTheme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply Catppuccin Frappé theme to the terminal.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall port for ttyd.";
    };
  };

  # ===========================================================================
  # MODULE IMPLEMENTATION
  # ===========================================================================

  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # SYSTEMD SERVICE
    # -------------------------------------------------------------------------
    systemd.services.konductor-ttyd = {
      description = "Konductor ttyd Web Terminal Service";
      documentation = [ "https://github.com/tsl0922/ttyd" ];

      after = [ "network.target" ];
      wants = [ "network.target" ];

      # IMPORTANT: Empty wantedBy means service does NOT start at boot.
      # Enable via cloud-init or manually: systemctl enable --now konductor-ttyd
      wantedBy = [ ];

      environment = {
        HOME = "/home/${cfg.user}";
        LANG = "C.UTF-8";
        TERM = cfg.terminalType;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart =
          let
            # Theme options for xterm.js (only if enabled)
            themeOpts = lib.optionals cfg.enableTheme [
              "-t 'theme=${themeJson}'"
              ''-t 'fontFamily="JetBrainsMono Nerd Font Mono", "JetBrains Mono", "Fira Code", monospace' ''
              "-t fontSize=14"
              "-t cursorBlink=true"
              "-t scrollback=10000"
            ];

            # User-provided client options
            extraOpts = lib.mapAttrsToList (k: v: "-t ${k}=${v}") cfg.clientOptions;

            # Optional flags
            optionalFlags = lib.optional (cfg.basePath != null) "--base-path ${cfg.basePath}"
              ++ lib.optional cfg.enableIPv6 "--ipv6"
              ++ lib.optional cfg.checkOrigin "--check-origin";

            # Shell command
            shellCmd = [ cfg.shell ] ++ cfg.shellArgs;
          in
          lib.concatStringsSep " " ([
            "${cfg.package}/bin/ttyd"
            "--writable"
            "--port ${toString cfg.port}"
            "--interface ${cfg.interface}"
            "--cwd ${toString cfg.workingDirectory}"
            "--max-clients ${toString cfg.maxClients}"
            "--terminal-type ${cfg.terminalType}"
          ] ++ optionalFlags ++ themeOpts ++ extraOpts ++ shellCmd);

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

        # -------------------------------------------------------------------
        # RESOURCE LIMITS
        # -------------------------------------------------------------------
        MemoryMax = "256M";
        TasksMax = toString (cfg.maxClients * 2 + 10);
      };
    };

    # -------------------------------------------------------------------------
    # FIREWALL
    # -------------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
