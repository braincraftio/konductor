# src/modules/restty-web-rw.nix
# NixOS module for Restty Web Terminal service (writable mode)
#
# Writable variant on port 7687 for interactive sessions.
# Use restty-web (port 7685) for read-only access.
#
# Enable via cloud-init:
#   runcmd:
#     - systemctl enable --now restty-web-rw

{ config, lib, pkgs, ... }:

let
  cfg = config.services.restty-web-rw;
  resttyWeb = import ../programs/restty-web { inherit pkgs lib; };

in
{
  options.services.restty-web-rw = {
    enable = lib.mkEnableOption "Restty web terminal service (writable)";

    package = lib.mkOption {
      type = lib.types.package;
      default = resttyWeb.server;
      defaultText = lib.literalExpression "restty-web-server";
      description = "The restty-web server package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7687;
      description = "TCP port (default 7687 for writable mode).";
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
      description = "Shell for PTY sessions.";
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
      description = "Idle session timeout in seconds.";
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

    basePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Base path for reverse proxy.";
    };

    checkOrigin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reject WebSocket connections from different origins.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.restty-web-rw = {
      description = "Restty Web Terminal Service (writable)";
      documentation = [ "https://github.com/wiedymi/restty" ];

      after = [ "network.target" ] ++ lib.optional cfg.enableSSL "konductor.service";
      wants = [ "network.target" ];
      requires = lib.optional cfg.enableSSL "konductor.service";
      wantedBy = [ ];

      unitConfig = lib.mkIf cfg.enableSSL {
        ConditionPathExists = [ cfg.sslCertPath cfg.sslKeyPath ];
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
            sslFlags = lib.optionals cfg.enableSSL [
              "--ssl" "--ssl-cert" cfg.sslCertPath "--ssl-key" cfg.sslKeyPath
            ];
            optionalFlags = lib.optional (cfg.basePath != null) "--base-path ${cfg.basePath}"
              ++ lib.optional cfg.checkOrigin "--check-origin";
          in
          lib.concatStringsSep " " ([
            "${cfg.package}/bin/restty-web-server"
            "--writable"
            "--port" (toString cfg.port)
            "--host" cfg.host
            "--working-directory" (toString cfg.workingDirectory)
            "--max-sessions" (toString cfg.maxSessions)
            "--idle-timeout" (toString cfg.idleTimeout)
          ] ++ sslFlags ++ optionalFlags);

        Restart = "always";
        RestartSec = 5;

        NoNewPrivileges = false;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.workingDirectory "/home/${cfg.user}" ];
        ReadOnlyPaths = lib.mkIf cfg.enableSSL [ (builtins.dirOf cfg.sslCertPath) ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = false;
        MemoryMax = "6G";
        TasksMax = 1024;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
