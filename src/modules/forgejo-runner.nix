# src/modules/forgejo-runner.nix
# NixOS module: Forgejo Actions runner daemon with registration retry.
#
# Owns every runtime piece of the runner: the package on the system and the
# runner user's profile, forgejo-runner.service, forgejo-runner-register.service
# and its timer. Disabled by default.
#
# Registration flow:
#   cloud-init writes <stateDir>/secret and <stateDir>/url, then creates
#   ~/.config/forgejo-runner/.runner via `forgejo-runner create-runner-file`.
#   If that fails (Forgejo not reachable yet), forgejo-runner-register.timer
#   retries every 30s until .runner exists, then starts the daemon.
#
# PKI trust comes from konductor-pki-trust.service (pki.nix), which writes the
# extended CA bundle used through SSL_CERT_FILE.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.konductor.forgejoRunner;
  inherit (config.users.users.${cfg.user}) home;
  configDir = "${home}/.config/forgejo-runner";
  runnerFile = "${configDir}/.runner";
  runnerBin = lib.getExe cfg.package;
  caBundle = "/etc/konductor/pki/bundle/ca-bundle.crt";
in
{
  options.konductor.forgejoRunner = {
    enable = lib.mkEnableOption "the Forgejo Actions runner daemon";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "forgejo-runner package (the BrainCraft fork built from the forgejo-runner-src flake input).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "runner";
      description = "Existing user the runner daemon and registration run as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/konductor/forgejo-runner";
      description = "Directory holding the registration `secret` and `url` files.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "konductor.forgejoRunner.enable requires konductor.forgejoRunner.package (declare the forgejo-runner-src flake input).";
      }
    ];

    environment.systemPackages = [ cfg.package ];
    users.users.${cfg.user}.packages = [ cfg.package ];

    systemd = {
      services = {
        forgejo-runner = {
          description = "Forgejo Actions Runner";
          # wantedBy auto-starts on boot; ConditionPathExists skips the unit until
          # registration has created .runner (first boot: cloud-init starts it).
          after = [
            "network-online.target"
            "docker.service"
            "konductor-pki-trust.service"
            "konductor.service"
          ];
          wants = [
            "network-online.target"
            "docker.service"
            "konductor-pki-trust.service"
            "konductor.service"
          ];
          wantedBy = [ "multi-user.target" ];
          # Survive long CI jobs and transient Forgejo outages (scale-to-zero, redeploys)
          startLimitIntervalSec = 300;
          startLimitBurst = 10;
          unitConfig.ConditionPathExists = runnerFile;
          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = "users";
            WorkingDirectory = home;
            # proxy.env (cloud-init, proxy deployments) gives the daemon
            # HTTP_PROXY/HTTPS_PROXY/NO_PROXY for cloning GitHub-hosted actions.
            EnvironmentFile = [ "-/etc/konductor/proxy.env" ];
            Environment = [
              "HOME=${home}"
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
              "DOCKER_HOST=unix:///var/run/docker.sock"
              # OVMF EFI firmware for QEMU (required for QCOW2 builds)
              "OVMF_CODE=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
              "OVMF_VARS=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd"
              "DOCKER_BUILDKIT=1"
              "CI=true"
              # NixOS /etc/ssl/certs is immutable; konductor-pki-trust writes the extended bundle
              "SSL_CERT_FILE=${caBundle}"
            ];
            ExecStart = "${runnerBin} daemon --config ${configDir}/config.yaml";
            # The runner retries connections internally; Restart=always covers crashes.
            Restart = "always";
            RestartSec = 15;
          };
        };

        # Started only by the timer (no wantedBy).
        forgejo-runner-register = {
          description = "Retry Forgejo Runner Registration";
          after = [
            "network-online.target"
            "konductor-pki-trust.service"
          ];
          wants = [ "network-online.target" ];
          unitConfig.ConditionPathExists = "!${runnerFile}";
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = "users";
            Environment = [
              "HOME=${home}"
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
              "SSL_CERT_FILE=${caBundle}"
            ];
            ExecStart = pkgs.writeShellScript "forgejo-runner-register-retry" ''
              if [ -f "${runnerFile}" ]; then
                echo "forgejo-runner-register: already registered, nothing to do"
                exit 0
              fi

              if [ ! -f "${cfg.stateDir}/secret" ] || [ ! -f "${cfg.stateDir}/url" ]; then
                echo "forgejo-runner-register: secret or url not configured, skipping"
                exit 1
              fi

              SECRET=$(${pkgs.coreutils}/bin/cat "${cfg.stateDir}/secret")
              URL=$(${pkgs.coreutils}/bin/cat "${cfg.stateDir}/url")
              NAME=$(${lib.getExe' pkgs.hostname "hostname"})

              echo "forgejo-runner-register: attempting registration against $URL..."
              ${pkgs.coreutils}/bin/mkdir -p "${configDir}"

              if ${runnerBin} \
                --config "${configDir}/config.yaml" \
                create-runner-file \
                --secret "$SECRET" \
                --instance "$URL" \
                --name "$NAME" \
                --connect; then
                echo "forgejo-runner-register: registration succeeded, starting runner"
                /run/current-system/sw/bin/systemctl start forgejo-runner.service || true
                /run/current-system/sw/bin/systemctl stop forgejo-runner-register.timer || true
                exit 0
              else
                echo "forgejo-runner-register: registration failed, timer will retry"
                exit 1
              fi
            '';
          };
        };
      };

      timers.forgejo-runner-register = {
        description = "Retry Forgejo Runner Registration Timer";
        wantedBy = [ "timers.target" ];
        unitConfig.ConditionPathExists = [
          # Only activate when registration credentials exist (profile-provided)
          "${cfg.stateDir}/secret"
          "${cfg.stateDir}/url"
          # Stop once registration is complete
          "!${runnerFile}"
        ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "30s";
          AccuracySec = "5s";
        };
      };
    };
  };
}
