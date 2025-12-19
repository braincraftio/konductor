# src/qcow2/default.nix
# QCOW2 VM build using nixos-generators
#
# Services installed but not auto-started (lean boot).
# Self-hosting tools fetched on-demand via: nix develop konductor#konductor
#
# Cloud-init workflow:
#   1. Start services: systemctl start docker libvirtd
#   2. Enter devshell: nix develop konductor#konductor

{ pkgs, lib, nixos-generators, system, ... }:

let
  versions = import ../lib/versions.nix;
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions; };

  # Import packages with wrapped config (hermetic linters/formatters)
  devshellPackages = import ../packages {
    inherit pkgs lib versions config;
  };

in
{
  # QCOW2 VM image
  image = nixos-generators.nixosGenerate {
    inherit system;
    format = "qcow";
    # Note: copyChannel is not exposed by nixos-generators wrapper
    # Channel copy prevented via installer.cloneConfig = false below
    modules = [
      {
        # Basic system configuration
        # stateVersion from src/lib/versions.nix nixos.stateVersion
        system.stateVersion = versions.nixos.stateVersion;
        networking.hostName = "konductor";

        # =====================================================================
        # Image Size Optimization
        # =====================================================================
        # Disable documentation (saves ~1.5GB: ghc-doc, rust-docs, man pages)
        documentation.enable = false;
        documentation.doc.enable = false;
        documentation.info.enable = false;
        documentation.man.enable = false;
        documentation.nixos.enable = false;

        # Don't include default packages (nano, perl, rsync, strace)
        environment.defaultPackages = lib.mkForce [];

        # Disable command-not-found (requires nixpkgs channel)
        programs.command-not-found.enable = false;

        # TODO: Investigate channel copy reduction (~400MB)
        # - nixos-generators doesn't expose `copyChannel` parameter from make-disk-image.nix
        # - `system.installer.channel.enable` doesn't exist in NixOS
        # - Options: 1) Use make-disk-image.nix directly instead of nixos-generators
        #            2) Create custom format module that passes copyChannel = false
        #            3) Find correct NixOS option to disable channel copy
        # - See: nixos/lib/make-disk-image.nix in nixpkgs
        networking.useNetworkd = true;
        systemd.network.enable = true;
        systemd.network.networks."10-ethernet" = {
          matchConfig.Type = "ether";
          networkConfig.DHCP = "yes";
        };

        # Users
        users.users.kc2 = {
          isNormalUser = true;
          inherit (users.kc2) uid home;
          description = users.kc2.gecos;
          extraGroups = [ "wheel" "docker" "libvirtd" "kvm" ];
        };

        users.users.kc2admin = {
          isNormalUser = true;
          inherit (users.kc2admin) uid home;
          description = users.kc2admin.gecos;
          extraGroups = [ "wheel" "docker" "libvirtd" "kvm" ];
        };

        # Sudo without password
        security.sudo.wheelNeedsPassword = false;

        # Direnv for automatic flake loading
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        # /etc/skel/.envrc - copied to new user home directories
        # Auto-loads flake offline and picks up .env for secrets (KubeVirt secret mounts)
        environment.etc."skel/.envrc".text = ''
          # Konductor airgap configuration
          # Loads pre-cached flake from /opt/konductor (offline mode)
          use flake /opt/konductor --offline

          # Load secrets from .env (supports KubeVirt secret mounts)
          dotenv_if_exists .env
          dotenv_if_exists "$HOME/.env"
        '';

        # /etc/profile.d/konductor-proxy.sh - sources proxy env for shell sessions
        # Cloud-init writes /etc/konductor/proxy.env, this script sources it
        environment.etc."profile.d/konductor-proxy.sh".text = ''
          # Source proxy configuration if present (set by cloud-init)
          if [ -f /etc/konductor/proxy.env ]; then
            set -a
            . /etc/konductor/proxy.env
            set +a
          fi
        '';

        # Packages: devshell defaults + essentials
        # Self-hosting tools (docker, qemu, libvirt) via: nix develop konductor#konductor
        environment.systemPackages = devshellPackages.default
          ++ (with pkgs; [
            git
            gh
            gnumake
            cachix
          ]);

        # Environment variables from centralized configuration
        environment.variables = lib.mapAttrs (_name: value: lib.mkForce value) env;

        # Services configuration
        services = {
          # SSH for VM access
          openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "yes";
              PasswordAuthentication = true;
            };
          };

          # QEMU guest agent for VM management
          qemuGuest.enable = true;

          # Cloud-init for dynamic configuration
          cloud-init = {
            enable = true;
            network.enable = true;
          };
        };

        # Docker - installed but not started on boot
        # Start via: systemctl start docker
        virtualisation.docker = {
          enable = true;
          enableOnBoot = false;
        };

        # Libvirt - installed but not started on boot
        # Start via: systemctl start libvirtd
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            runAsRoot = true;
            swtpm.enable = true;
          };
        };

        # Don't auto-start libvirtd (cloud-init will start it if needed)
        systemd.services.libvirtd.wantedBy = lib.mkForce [ ];

        # 9p workspace mount service - auto-mounts /workspace if virtfs is available
        # Runs on boot with retries to handle device availability timing
        systemd.services.workspace-mount = {
          description = "Mount 9p workspace from host";
          after = [ "local-fs.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "mount-workspace" ''
              set -euo pipefail
              MOUNT_POINT="/workspace"
              MOUNT_TAG="host"
              MAX_RETRIES=5
              RETRY_DELAY=2

              # Create mount point if needed
              mkdir -p "$MOUNT_POINT"

              # Check if already mounted
              if mountpoint -q "$MOUNT_POINT"; then
                echo "Workspace already mounted"
                exit 0
              fi

              # Try to mount with retries (device may not be immediately available)
              for i in $(seq 1 $MAX_RETRIES); do
                if mount -t 9p -o trans=virtio "$MOUNT_TAG" "$MOUNT_POINT" 2>/dev/null; then
                  echo "Workspace mounted successfully"
                  exit 0
                fi
                echo "Mount attempt $i/$MAX_RETRIES failed, retrying in ''${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
              done

              echo "No 9p virtfs device available (VM started without -virtfs)"
              exit 0
            '';
          };
        };

        # =====================================================================
        # Proxy Configuration (Cloud-init Runtime)
        # =====================================================================
        # Applies proxy settings from cloud-init before nix-daemon starts.
        # Cloud-init writes /etc/konductor/proxy.env, this service creates
        # a systemd drop-in for nix-daemon to read it.
        #
        # Usage: Cloud-init user-data writes proxy.env file:
        #   write_files:
        #     - path: /etc/konductor/proxy.env
        #       content: |
        #         http_proxy=http://proxy.example.com:8080
        #         https_proxy=http://proxy.example.com:8080
        #         HTTP_PROXY=http://proxy.example.com:8080
        #         HTTPS_PROXY=http://proxy.example.com:8080
        #         no_proxy=localhost,127.0.0.1,10.0.0.0/8
        #         NO_PROXY=localhost,127.0.0.1,10.0.0.0/8
        systemd.services.konductor-proxy-setup = {
          description = "Configure proxy for nix-daemon from cloud-init";
          before = [ "nix-daemon.service" ];
          wantedBy = [ "nix-daemon.service" ];
          unitConfig = {
            ConditionPathExists = "/etc/konductor/proxy.env";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "setup-nix-proxy" ''
              set -euo pipefail
              PROXY_ENV="/etc/konductor/proxy.env"
              DROPIN_DIR="/run/systemd/system/nix-daemon.service.d"

              echo "Configuring nix-daemon proxy from $PROXY_ENV"

              # Create drop-in directory
              mkdir -p "$DROPIN_DIR"

              # Create drop-in that loads the proxy environment file
              cat > "$DROPIN_DIR/proxy.conf" << EOF
              [Service]
              EnvironmentFile=$PROXY_ENV
              EOF

              # Reload systemd to pick up the drop-in
              systemctl daemon-reload

              echo "Proxy configuration applied to nix-daemon"
            '';
          };
        };

        # Disk size for VM
        virtualisation.diskSize = lib.mkDefault (20 * 1024); # 20GB (lean image)

        # Virtio drivers for performance
        boot.initrd.availableKernelModules = [
          "virtio_net"
          "virtio_pci"
          "virtio_mmio"
          "virtio_blk"
          "virtio_scsi"
          "virtio_balloon"
          "virtio_console"
          "9p"
          "9pnet_virtio"
        ];

        # Spice/QEMU guest tools for clipboard, display, etc.
        services.spice-vdagentd.enable = true;

        # Nix configuration
        nix = {
          settings = {
            experimental-features = [ "nix-command" "flakes" ];
            auto-optimise-store = true;
            accept-flake-config = true;
            trusted-users = [ "root" "@wheel" ];
            substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
            trusted-substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };
          # Pre-configured flake registry
          # Usage: nix develop konductor#konductor
          registry.konductor = {
            from = { type = "indirect"; id = "konductor"; };
            to = { type = "github"; owner = "braincraftio"; repo = "konductor"; };
          };
        };
      }
    ];
  };
}
