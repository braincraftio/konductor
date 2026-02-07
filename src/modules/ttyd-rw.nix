# src/modules/ttyd-rw.nix
# NixOS module for Konductor ttyd Web Terminal service (writable)
#
# Writable variant on port 7683 for interactive sessions.
# Use konductor-ttyd (port 7681) for read-only access.
#
# Enable via cloud-init:
#   runcmd:
#     - systemctl enable --now konductor-ttyd-rw

{ config, lib, pkgs, ... }:

let
  cfg = config.services.konductor-ttyd-rw;
  ttydProgram = import ../programs/ttyd { inherit pkgs lib; };
  themeJson = builtins.toJSON ttydProgram.theme;

in
{
  options.services.konductor-ttyd-rw = {
    enable = lib.mkEnableOption "Konductor ttyd web terminal service (writable)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ttyd;
      defaultText = lib.literalExpression "pkgs.ttyd";
      description = "The ttyd package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7683;
      description = "TCP port (default 7683 for writable mode).";
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
      description = "Arguments to pass to the shell.";
    };

    workingDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/workspace";
      description = "Initial working directory for shell sessions.";
    };

    maxClients = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10;
      description = "Maximum number of concurrent clients.";
    };

    terminalType = lib.mkOption {
      type = lib.types.str;
      default = "xterm-256color";
      description = "Terminal type to report.";
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
      description = "Base path for reverse proxy.";
    };

    clientOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional xterm.js client options.";
    };

    enableTheme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply Catppuccin Frappe theme.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall port.";
    };

    enableSSL = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSL/TLS.";
    };

    sslCertPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/konductor/pki/vm/wildcard.crt";
      description = "Path to SSL certificate.";
    };

    sslKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/konductor/pki/vm/wildcard.key";
      description = "Path to SSL private key.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.konductor-ttyd-rw = {
      description = "Konductor ttyd Web Terminal Service (writable)";
      documentation = [ "https://github.com/tsl0922/ttyd" ];

      after = [ "network.target" ] ++ lib.optional cfg.enableSSL "konductor.service";
      wants = [ "network.target" ];
      requires = lib.optional cfg.enableSSL "konductor.service";
      wantedBy = [ ];

      unitConfig = lib.mkIf cfg.enableSSL {
        ConditionPathExists = [ cfg.sslCertPath cfg.sslKeyPath ];
      };

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
            themeOpts = lib.optionals cfg.enableTheme [
              "-t 'theme=${themeJson}'"
              ''-t 'fontFamily="JetBrainsMono Nerd Font Mono", "JetBrains Mono", "Fira Code", monospace' ''
              "-t fontSize=14"
              "-t cursorBlink=true"
              "-t scrollback=10000"
            ];
            extraOpts = lib.mapAttrsToList (k: v: "-t ${k}=${v}") cfg.clientOptions;
            sslFlags = lib.optionals cfg.enableSSL [
              "--ssl" "--ssl-cert ${cfg.sslCertPath}" "--ssl-key ${cfg.sslKeyPath}"
            ];
            optionalFlags = lib.optional (cfg.basePath != null) "--base-path ${cfg.basePath}"
              ++ lib.optional cfg.enableIPv6 "--ipv6"
              ++ lib.optional cfg.checkOrigin "--check-origin";
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
          ] ++ sslFlags ++ optionalFlags ++ themeOpts ++ extraOpts ++ shellCmd);

        Restart = "always";
        RestartSec = 5;

        # NoNewPrivileges disabled to allow sudo for admin terminals
        NoNewPrivileges = false;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.workingDirectory "/home/${cfg.user}" ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        # Heavy development workloads: Claude Code + LSPs + nested tmux
        # Single Claude session: ~1.2GB, 70+ tasks (gopls, pyright, tsserver)
        MemoryMax = "6G";
        TasksMax = 1024;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
