# src/qcow2/default.nix
# QCOW2 VM build using nixos-generators
#
# Full konductor environment pre-installed for immediate productivity.
# SSH in and start working - no additional setup required.
#
# Includes:
#   - All languages (Python, Go, Node, Rust)
#   - IDE tools (Neovim, tmux)
#   - Self-hosting tools (Docker, QEMU, libvirt)
#   - Linters, formatters, AI tools
#
# Services installed but not auto-started (lean boot).
# Start via cloud-init or: systemctl start docker libvirtd

{ pkgs, lib, nixos-generators, system, versions, programs, ... }:

let
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;
  shellContent = import ../lib/shell-content.nix { inherit lib; };

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions; };

  # Import packages with wrapped config (hermetic linters/formatters)
  devshellPackages = import ../packages {
    inherit pkgs lib versions config;
  };

  # Konductor self-hosting packages (docker, qemu, libvirt, etc.)
  inherit (devshellPackages) konductor;

in
{
  # QCOW2 VM image
  # Use qcow-efi for proper 4K partition alignment (ESP starts at 8MiB)
  # The "qcow" format uses hybrid partition table with BIOS partition at sector 0,
  # which causes alignment warnings and suboptimal I/O on Ceph RBD.
  image = nixos-generators.nixosGenerate {
    inherit system;
    format = "qcow-efi";
    # Note: copyChannel is not exposed by nixos-generators wrapper
    # Channel copy prevented via installer.cloneConfig = false below
    modules = [
      {
        # Basic system configuration
        # stateVersion from src/lib/versions.nix nixos.stateVersion
        system.stateVersion = versions.nixos.stateVersion;
        networking = {
          hostName = "konductor";
          useNetworkd = true;
        };

        # =====================================================================
        # Image Size Optimization
        # =====================================================================
        # Disable documentation (saves ~1.5GB: ghc-doc, rust-docs, man pages)
        documentation = {
          enable = false;
          doc.enable = false;
          info.enable = false;
          man.enable = false;
          nixos.enable = false;
        };

        # Disable command-not-found (requires nixpkgs channel)
        programs.command-not-found.enable = false;

        # TODO: Investigate channel copy reduction (~400MB)
        # - nixos-generators doesn't expose `copyChannel` parameter from make-disk-image.nix
        # - `system.installer.channel.enable` doesn't exist in NixOS
        # - Options: 1) Use make-disk-image.nix directly instead of nixos-generators
        #            2) Create custom format module that passes copyChannel = false
        #            3) Find correct NixOS option to disable channel copy
        # - See: nixos/lib/make-disk-image.nix in nixpkgs

        # Users
        users.users = {
          kc2 = {
            isNormalUser = true;
            inherit (users.kc2) uid home;
            description = users.kc2.gecos;
            extraGroups = [ "docker" "libvirtd" "kvm" ];
          };
          kc2admin = {
            isNormalUser = true;
            inherit (users.kc2admin) uid home;
            description = users.kc2admin.gecos;
            extraGroups = [ "wheel" "docker" "libvirtd" "kvm" ];
          };
          runner = {
            isNormalUser = true;
            inherit (users.runner) uid home;
            description = users.runner.gecos;
            extraGroups = [ "docker" "libvirtd" "kvm" ];
          };
        };

        # Sudo without password for wheel group
        security = {
          sudo = {
            wheelNeedsPassword = false;
            # Runner sudoers for docker and nix commands (CI/CD builds)
            extraRules = [
              {
                users = [ "runner" ];
                commands = [
                  { command = "/run/current-system/sw/bin/docker"; options = [ "NOPASSWD" ]; }
                  { command = "/run/current-system/sw/bin/nix"; options = [ "NOPASSWD" ]; }
                  { command = "/run/current-system/sw/bin/nix-build"; options = [ "NOPASSWD" ]; }
                  { command = "/run/current-system/sw/bin/nix-shell"; options = [ "NOPASSWD" ]; }
                  { command = "/run/current-system/sw/bin/nix-env"; options = [ "NOPASSWD" ]; }
                  { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
                ];
              }
            ];
          };
        };

        # Direnv for automatic flake loading with trusted paths
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
          # Auto-trust .envrc in these locations (writes to /etc/direnv/direnv.toml)
          settings = {
            whitelist = {
              prefix = [ "~" "/opt/konductor" "/workspace" "/home" ];
            };
          };
        };

        # =====================================================================
        # Environment Configuration
        # =====================================================================
        environment = {
          # Don't include default packages (nano, perl, rsync, strace)
          defaultPackages = lib.mkForce [ ];

          # /etc/skel - Shell Configuration (copied to new user home dirs)
          # Same shell experience as devshell and OCI container
          etc = {
            "skel/.bashrc".text = shellContent.bashrcContentStandalone;
            "skel/.bash_profile".text = shellContent.bashProfileContent;
            "skel/.inputrc".text = shellContent.inputrcContent;
            "skel/.gitconfig".text = shellContent.gitconfigContent;
            "skel/.config/starship.toml".text = config.shell.starship.configContent;

            # /etc/skel/.envrc - for project .env files only (packages pre-installed)
            "skel/.envrc".text = ''
              # Konductor VM - all packages pre-installed system-wide
              # This .envrc is for project-specific env vars only
              dotenv_if_exists .env
              dotenv_if_exists "$HOME/.env"
            '';

            # Note: direnv whitelist is in /etc/direnv/direnv.toml via programs.direnv.settings
            # No user-level direnv.toml needed since NixOS sets DIRENV_CONFIG=/etc/direnv

            # /etc/profile.d/konductor-proxy.sh - sources proxy env for shell sessions
            # Cloud-init writes /etc/konductor/proxy.env, this script sources it
            "profile.d/konductor-proxy.sh".text = ''
              # Source proxy configuration if present (set by cloud-init)
              if [ -f /etc/konductor/proxy.env ]; then
                set -a
                . /etc/konductor/proxy.env
                set +a
              fi
            '';

            # /etc/profile.d/konductor-env.sh - sets up language paths and tools
            # This ensures all users get the full konductor experience on login
            "profile.d/konductor-env.sh".text = ''
              # =====================================================================
              # Konductor Environment Setup
              # =====================================================================
              # Copy shell configs from /etc/skel if missing (first login setup)
              # Use -L to dereference symlinks (nix store files are read-only)
              if [ ! -f "$HOME/.bashrc" ] && [ -f /etc/skel/.bashrc ]; then
                cp -L /etc/skel/.bashrc "$HOME/"
                cp -L /etc/skel/.bash_profile "$HOME/" 2>/dev/null || true
                cp -L /etc/skel/.inputrc "$HOME/" 2>/dev/null || true
                cp -L /etc/skel/.gitconfig "$HOME/" 2>/dev/null || true
                mkdir -p "$HOME/.config"
                cp -L /etc/skel/.config/starship.toml "$HOME/.config/" 2>/dev/null || true
              fi
              # Note: direnv whitelist is at /etc/direnv/direnv.toml (NixOS system config)

              # Language paths
              export GOPATH="''${GOPATH:-$HOME/go}"
              export GOBIN="$GOPATH/bin"
              export PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
              export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"

              # Create directories if they don't exist
              mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg" 2>/dev/null || true
              mkdir -p "$PNPM_HOME" 2>/dev/null || true
              mkdir -p "$CARGO_HOME" 2>/dev/null || true

              # Update PATH with language bin directories
              export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

              # Python venv activation (if exists in current directory)
              if [ -d .venv ]; then
                source .venv/bin/activate 2>/dev/null || true
              fi

              # Neovim configuration
              ${programs.neovim.shellHook}

              # Tmux configuration
              ${programs.tmux.shellHook}
            '';
          };

          # Full Konductor Package Set
          # Complete konductor devshell packages pre-installed for immediate use.
          # SSH in and start working - no `nix develop` required.
          systemPackages = devshellPackages.default
            # All languages
            ++ devshellPackages.pythonPackages
            ++ devshellPackages.goPackages
            ++ devshellPackages.nodejsPackages
            ++ devshellPackages.rustPackages
            # IDE tools (neovim + tmux from programs)
            ++ programs.neovim.packages
            ++ programs.tmux.packages
            ++ devshellPackages.idePackages
            # Self-hosting tools (docker, qemu, libvirt, etc.)
            ++ konductor.packages
            # Essentials
            ++ (with pkgs; [
            git
            gh
            gnumake
            cachix
          ]);

          # Environment Variables
          # Includes base env + language-specific + konductor settings
          variables = lib.mapAttrs (_name: value: lib.mkForce value) (env // {
            # Python
            UV_SYSTEM_PYTHON = "1";
            PYTHONDONTWRITEBYTECODE = "1";
            # Go
            GO111MODULE = "on";
            CGO_ENABLED = "1";
            # Node
            NODE_ENV = "development";
            # Rust
            RUST_BACKTRACE = "1";
            # Docker
            DOCKER_BUILDKIT = "1";
            # Konductor
            KONDUCTOR_SHELL = "konductor";
          });
        };

        # =====================================================================
        # Systemd Configuration
        # =====================================================================
        systemd = {
          network = {
            enable = true;
            networks."10-ethernet" = {
              matchConfig.Type = "ether";
              networkConfig.DHCP = "yes";
            };
          };

          services = {
            # Don't auto-start libvirtd (cloud-init will start it if needed)
            libvirtd.wantedBy = lib.mkForce [ ];

            # 9p workspace mount service - auto-mounts /workspace if virtfs is available
            # Runs on boot with retries to handle device availability timing
            workspace-mount = {
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
            konductor-proxy-setup = {
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
          };
        };

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

          # Spice/QEMU guest tools for clipboard, display, etc.
          spice-vdagentd.enable = true;
        };

        # =====================================================================
        # Virtualisation Configuration
        # =====================================================================
        virtualisation = {
          # Disk size for VM
          diskSize = lib.mkDefault (20 * 1024); # 20GB (lean image)

          # Docker - installed but not started on boot
          # Start via: systemctl start docker
          docker = {
            enable = true;
            enableOnBoot = false;
          };

          # Libvirt - installed but not started on boot
          # Start via: systemctl start libvirtd
          libvirtd = {
            enable = true;
            qemu = {
              package = pkgs.qemu_kvm;
              runAsRoot = true;
              swtpm.enable = true;
            };
          };
        };

        # =====================================================================
        # Boot Configuration
        # =====================================================================
        boot = {
          # Use latest kernel for best hardware support and security
          kernelPackages = pkgs.linuxPackages_latest;

          # =====================================================================
          # Storage Optimization for Ceph RBD Block Devices
          # =====================================================================
          # Aligned for 4KB Ceph BlueStore allocation (bluestore_min_alloc_size_ssd)
          # See: Pulumi.optiplex-rook-ceph.yaml ceph_config_override

          # I/O scheduler: none for virtio-blk (Ceph handles its own scheduling)
          kernelParams = [
            "elevator=none"
            "scsi_mod.use_blk_mq=1"
          ];

          # Kernel tuning for block I/O on Ceph
          kernel.sysctl = {
            # Writeback tuning - larger dirty buffers for batch writes
            "vm.dirty_ratio" = 40;
            "vm.dirty_background_ratio" = 10;
            "vm.dirty_expire_centisecs" = 3000;
            "vm.dirty_writeback_centisecs" = 500;

            # Reduce swappiness (prefer keeping pages in memory)
            "vm.swappiness" = 10;

            # Increase readahead for sequential I/O (matches rbd_readahead_max_bytes)
            "vm.vfs_cache_pressure" = 50;
          };

          # Virtio drivers for performance
          initrd.availableKernelModules = [
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
        };

        # Filesystem mount options optimized for Ceph RBD
        fileSystems."/" = {
          options = [
            "noatime" # Reduce metadata writes
            "nodiratime" # Reduce directory access time updates
            "discard" # TRIM/unmap for thin provisioning
            "commit=60" # Increase journal commit interval (seconds)
          ];
        };

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
          # Pre-configured flake registry for updates/customization
          # All tools pre-installed - this registry is for advanced use
          registry.konductor = {
            from = { type = "indirect"; id = "konductor"; };
            to = { type = "github"; owner = "braincraftio"; repo = "konductor"; };
          };
        };
      }
    ];
  };
}
