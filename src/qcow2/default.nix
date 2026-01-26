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

{
  pkgs,
  lib,
  nixos-generators,
  inputs,
  system,
  versions,
  programs,
  ...
}:

let
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;
  shellContent = import ../lib/shell-content.nix { inherit lib; };

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions; };

  # Import packages with wrapped config (hermetic linters/formatters)
  devshellPackages = import ../packages {
    inherit
      pkgs
      lib
      versions
      config
      ;
  };

  # Konductor self-hosting packages (docker, qemu, libvirt, etc.)
  inherit (devshellPackages) konductor;

  # Systemd mount service template for virtio disk mounting
  mountService = import ./konductor-mount-template.nix { inherit pkgs; };

  # PKI module for VM identity and certificate chain of trust
  pkiModule = import ../modules/pki.nix;

  # Common home-manager configuration for built-in users
  # Provisions shell configs (.bashrc, .bash_profile, etc.) at build time
  homeManagerUserConfig = {
    home.file.".bashrc".text = shellContent.bashrcContentStandalone;
    home.file.".bash_profile".text = shellContent.bashProfileContent;
    home.file.".inputrc".text = shellContent.inputrcContent;
    home.file.".config/starship.toml".text = config.shell.starship.configContent;
    home.file.".envrc".text = ''
      # Konductor VM - all packages pre-installed system-wide
      # This .envrc is for project-specific env vars only
      dotenv_if_exists .env
      dotenv_if_exists "$HOME/.env"
    '';
    home.stateVersion = versions.nixos.stateVersion;
  };

  # Shared NixOS configuration module for both qcow2 image and nixos-rebuild
  # This allows live updates to running VMs via: nixos-rebuild switch --flake .#konductor
  konductorModule = {
    # Import the konductor mount service template, PKI module, and home-manager
    imports = [
      mountService
      pkiModule
      inputs.home-manager.nixosModules.home-manager
    ];

    # Basic system configuration
    # stateVersion from src/lib/versions.nix nixos.stateVersion
    system.stateVersion = versions.nixos.stateVersion;
    networking = {
      hostName = "konductor";
      useNetworkd = true;

      # =====================================================================
      # nftables Configuration for Docker-dev Kubernetes Access
      # =====================================================================
      # Uses native nftables instead of iptables translation layer.
      # The iptables-nft -C (check) command is unreliable with interface matching.
      #
      # Architecture:
      #   Laptop (192.168.x.x) → Konductor VM (192.168.1.83:443)
      #     → DNAT → Envoy Gateway LB VIP (10.5.0.241:443)
      #       → Kubernetes Service → Pod
      #
      # Interface wildcards (enp*, ens*, eth*) match all external interfaces.
      # Rules are always present but only effective when docker-dev network exists
      # and 10.5.0.241 is routable via Cilium L2 announcement.
      nftables = {
        enable = true;
        tables.docker-dev-nat = {
          family = "ip";
          content = ''
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;

              # DNAT HTTP/HTTPS to Envoy Gateway LoadBalancer VIP
              # Matches all external interfaces (enp*, ens*, eth*)
              iifname "enp*" tcp dport 80 dnat to 10.5.0.241:80 comment "HTTP to Envoy Gateway"
              iifname "enp*" tcp dport 443 dnat to 10.5.0.241:443 comment "HTTPS to Envoy Gateway"
              iifname "ens*" tcp dport 80 dnat to 10.5.0.241:80 comment "HTTP to Envoy Gateway"
              iifname "ens*" tcp dport 443 dnat to 10.5.0.241:443 comment "HTTPS to Envoy Gateway"
              iifname "eth*" tcp dport 80 dnat to 10.5.0.241:80 comment "HTTP to Envoy Gateway"
              iifname "eth*" tcp dport 443 dnat to 10.5.0.241:443 comment "HTTPS to Envoy Gateway"
            }

            chain forward {
              type filter hook forward priority filter; policy accept;

              # Allow traffic to/from docker-dev network (10.5.0.0/24)
              oifname "docker-dev" ip daddr 10.5.0.0/24 accept comment "Forward to docker-dev"
              iifname "docker-dev" ip saddr 10.5.0.0/24 accept comment "Forward from docker-dev"
            }

            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;

              # MASQUERADE for docker-dev traffic going to external destinations
              iifname "docker-dev" ip saddr 10.5.0.0/24 masquerade comment "SNAT docker-dev outbound"
            }
          '';
        };
      };
      # See: k9/docs/KONDUCTOR.networking-firewall-nat-masquerade-nix-firewall-iptables-nftables-omnibus.md
      # Note: DNAT/FORWARD/MASQUERADE handled by nftables.tables.docker-dev-nat above
      # This section only handles Docker-specific iptables chains (DOCKER-USER)
      nat = {
        enable = true;
        externalInterface = "enp+";
      };

      # Firewall extraCommands for Docker-specific chains only
      # DNAT/FORWARD/MASQUERADE are handled by native nftables above

      # Firewall configuration
      # Enable IP forwarding and allow traffic to Kubernetes services
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22    # SSH
          80    # HTTP (forwarded to Envoy Gateway)
          443   # HTTPS (forwarded to Envoy Gateway)
        ];
        # Trust Docker bridge networks for internal traffic
        trustedInterfaces = [ "docker-dev" "docker0" ];
      };
    };

    # =====================================================================
    # PKI - VM Identity and Certificate Chain of Trust
    # =====================================================================
    # Generates self-signed CA and wildcard certificate on first boot.
    # Supports mounted hypervisor CA for vertical PKI integration.
    #
    # Generated files:
    #   /etc/konductor/pki/vm/ca.{crt,key}        - VM-local CA
    #   /etc/konductor/pki/vm/wildcard.{crt,key}  - Wildcard cert for *.konductor.arpa
    #   /etc/konductor/pki/bundle/ca-bundle.crt   - Combined trust store
    #
    # Usage in Pulumi:
    #   ca_source: "provided"
    #   ca_certificate_base64: $(base64 -w0 /etc/konductor/pki/vm/ca.crt)
    #   ca_private_key_base64: $(base64 -w0 /etc/konductor/pki/vm/ca.key)
    #
    # Shell helpers:
    #   konductor-ca-base64  - Output base64 for Pulumi config
    #   konductor-ca-info    - Display CA certificate details
    konductor.pki = {
      enable = true;
      # Domain defaults to {hostname}.arpa (konductor.arpa)
      # Override with: konductor.pki.domain = "myvm.example.com";

      # Hypervisor CA paths (set via cloud-init or volume mount)
      # hypervisorCaPath = /etc/konductor/hypervisor-ca.crt;
      # hypervisorKeyPath = /etc/konductor/hypervisor-ca.key;
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

    # TODO: Investigate channel copy reduction (~400MB)
    # - nixos-generators doesn't expose `copyChannel` parameter from make-disk-image.nix
    # - `system.installer.channel.enable` doesn't exist in NixOS
    # - Options: 1) Use make-disk-image.nix directly instead of nixos-generators
    #            2) Create custom format module that passes copyChannel = false
    #            3) Find correct NixOS option to disable channel copy
    # - See: nixos/lib/make-disk-image.nix in nixpkgs

    # =====================================================================
    # MOTD (Message of the Day)
    # =====================================================================
    # Dynamic MOTD generated by konductor.service on boot.
    # Shows provenance identity and verification status.
    # Designed to be informative for newcomers, unimposing for daily users.
    users.motdFile = "/run/konductor/motd";

    # Users
    # All users in 'kc2' group (GID 1001) for shared directory access
    # Group must be defined BEFORE users reference it in extraGroups
    users.groups.kc2 = {
      gid = 1001;
      members = [ "kc2" "kc2admin" "runner" ];
    };

    users.users = {
      kc2 = {
        isNormalUser = true;
        inherit (users.kc2) uid home;
        description = users.kc2.gecos;
        extraGroups = [
          "kc2"
          "docker"
          "libvirtd"
          "kvm"
        ];
      };
      kc2admin = {
        isNormalUser = true;
        inherit (users.kc2admin) uid home;
        description = users.kc2admin.gecos;
        extraGroups = [
          "kc2"
          "wheel"
          "docker"
          "libvirtd"
          "kvm"
        ];
      };
      runner = {
        isNormalUser = true;
        inherit (users.runner) uid home;
        description = users.runner.gecos;
        # wheel needed for QCOW2 build (guestmount, virt-sparsify)
        extraGroups = [
          "kc2"
          "wheel"
          "docker"
          "libvirtd"
          "kvm"
        ];
        # CI toolchain in runner's user profile (/nix/var/nix/profiles/per-user/runner)
        # Defense in depth: packages available even if systemPackages changes
        packages = devshellPackages.ciPackages
          ++ programs.forgejo.runnerPackages
          ++ programs.forgejo.cliPackages
          ++ konductor.packages;
      };
    };

    # =====================================================================
    # Home Manager - Built-in User Home Directory Provisioning
    # =====================================================================
    # Declaratively provisions shell configs for built-in users at build time.
    # Dynamic users (cloud-init) still use /etc/skel via profile.d scripts.
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users = {
        kc2 = homeManagerUserConfig;
        kc2admin = homeManagerUserConfig;
        runner = homeManagerUserConfig;
      };
    };

    # Sudo without password for wheel group
    security = {
      sudo = {
        wheelNeedsPassword = false;
        # TODO: Remove runner from wheel and add explicit guestfs sudo rules:
        #   guestmount, guestunmount, virt-sparsify, mkdir, rm, rmdir
        # Explicit constraints are safer, more traceable, and auditable.
        # Runner sudoers for docker and nix commands (CI/CD builds)
        extraRules = [
          {
            users = [ "runner" ];
            commands = [
              {
                command = "/run/current-system/sw/bin/docker";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/nix";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/nix-build";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/nix-shell";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/nix-env";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/nixos-rebuild";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];
      };
    };

    # Programs configuration (consolidated to avoid repeated keys warning)
    programs = {
      # Disable command-not-found (requires nixpkgs channel)
      command-not-found.enable = false;

      # Bash shell configuration
      bash = {
        # Shell initialization (all bash shells)
        shellInit = ''
          # Language tool paths (complements profile.d/konductor-env.sh)
          export PATH="''${GOPATH:-$HOME/go}/bin:''${CARGO_HOME:-$HOME/.cargo}/bin:''${PNPM_HOME:-$HOME/.local/share/pnpm}:$PATH"
        '';
        # Interactive shell initialization
        interactiveShellInit = ''
          # Source Konductor bashrc for aliases if available
          if [ -n "$KONDUCTOR_BASHRC" ] && [ -f "$KONDUCTOR_BASHRC" ]; then
            source "$KONDUCTOR_BASHRC"
          fi
        '';
      };

      # Direnv for automatic flake loading with trusted paths
      direnv = {
        enable = true;
        nix-direnv.enable = true;
        # Auto-trust .envrc in these locations (writes to /etc/direnv/direnv.toml)
        settings = {
          whitelist = {
            prefix = [
              "~"
              "/opt/konductor"
              "/workspace"
              "/home"
            ];
          };
        };
      };

      # SSH client configuration (/etc/ssh/ssh_config)
      # Localhost:2222 for QCOW2 build VM access with auto-accept host keys
      ssh = {
        extraConfig = ''
          Host localhost
              Port 2222
              StrictHostKeyChecking no
              UserKnownHostsFile /dev/null
              LogLevel ERROR
              ConnectTimeout 5
        '';
      };

      # Git global configuration (/etc/gitconfig)
      # System-level defaults - user ~/.gitconfig can override
      git = {
        enable = true;
        config = {
          init.defaultBranch = "main";
          core = {
            editor = "nvim";
            pager = "bat";
          };
          color.ui = "auto";
          pull.rebase = true;
          # Credential helpers - use stable paths for NixOS
          credential.helper = [
            ""
            "cache --timeout=3600"
          ];
          "credential \"https://github.com\"".helper = [
            ""
            "!/run/current-system/sw/bin/gh auth git-credential"
          ];
          "credential \"https://gist.github.com\"".helper = [
            ""
            "!/run/current-system/sw/bin/gh auth git-credential"
          ];
          "credential \"https://git.braincraft.io\"".helper = [
            ""
            "cache --timeout=3600"
          ];
          # Aliases
          alias = {
            st = "status";
            co = "checkout";
            br = "branch";
            ci = "commit";
            lg = "log --oneline --graph --decorate";
          };
          # Safe directories for shared repos
          safe.directory = [
            "/opt/konductor"
            "/home/Git"
            "/workspace"
            "*"
          ];
        };
      };
    };

    # =====================================================================
    # Environment Configuration
    # =====================================================================
    environment = {
      # Don't include default packages (nano, perl, rsync, strace)
      defaultPackages = lib.mkForce [ ];

      # Session variables (PAM-level - available to all contexts including systemd services)
      # Uses @{HOME} syntax for PAM variable expansion
      sessionVariables = {
        # CI environment marker
        CI = "true";
        # Hermetic bash configuration (from devshell)
        KONDUCTOR_BASHRC = config.shell.bash.env.KONDUCTOR_BASHRC;
        KONDUCTOR_INPUTRC = config.shell.bash.env.KONDUCTOR_INPUTRC;
        # Language paths (PAM @{HOME} expansion)
        GOPATH = "@{HOME}/go";
        CARGO_HOME = "@{HOME}/.cargo";
        PNPM_HOME = "@{HOME}/.local/share/pnpm";
        # OVMF EFI firmware paths for QEMU (from konductor.env)
        OVMF_CODE = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
        OVMF_VARS = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
        # Docker buildkit
        DOCKER_BUILDKIT = "1";
      };

      # /etc/skel - Shell Configuration (copied to new user home dirs)
      # Same shell experience as devshell and OCI container
      etc = {
        "skel/.bashrc".text = shellContent.bashrcContentStandalone;
        "skel/.bash_profile".text = shellContent.bashProfileContent;
        "skel/.inputrc".text = shellContent.inputrcContent;
        # Note: .gitconfig is NOT in skel - git config is at system level via programs.git
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
          # Note: .gitconfig is NOT copied - git uses /etc/gitconfig (system level)
          # Check each file independently so partial setups get completed
          [ ! -f "$HOME/.bashrc" ] && [ -f /etc/skel/.bashrc ] && cp -L /etc/skel/.bashrc "$HOME/"
          [ ! -f "$HOME/.bash_profile" ] && [ -f /etc/skel/.bash_profile ] && cp -L /etc/skel/.bash_profile "$HOME/"
          [ ! -f "$HOME/.inputrc" ] && [ -f /etc/skel/.inputrc ] && cp -L /etc/skel/.inputrc "$HOME/"
          [ ! -f "$HOME/.envrc" ] && [ -f /etc/skel/.envrc ] && cp -L /etc/skel/.envrc "$HOME/"
          if [ ! -f "$HOME/.config/starship.toml" ] && [ -f /etc/skel/.config/starship.toml ]; then
            mkdir -p "$HOME/.config"
            cp -L /etc/skel/.config/starship.toml "$HOME/.config/"
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

          # Starship prompt (initialize here for first login, also in .bashrc for subshells)
          # Skip on non-interactive or dumb terminals
          if command -v starship >/dev/null 2>&1 && [ -t 0 ] && [[ "''${TERM:-dumb}" != "dumb" ]]; then
            eval "$(starship init bash)"
          fi

          # Direnv (initialize here for first login, also in .bashrc for subshells)
          if command -v direnv >/dev/null 2>&1; then
            eval "$(direnv hook bash)"
          fi
        '';
      };

      # Full Konductor Package Set
      # Complete konductor devshell packages pre-installed for immediate use.
      # SSH in and start working - no `nix develop` required.
      systemPackages =
        devshellPackages.default
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
        # Forgejo CI/CD tools (runner + cli)
        ++ programs.forgejo.runnerPackages
        ++ programs.forgejo.cliPackages
        # Essentials
        ++ (with pkgs; [
          git
          gh
          gnumake
          cachix
        ]);

      # Environment Variables
      # Includes base env + language-specific + konductor settings
      variables = lib.mapAttrs (_name: value: lib.mkForce value) (
        env
        // {
          # BASH_ENV: Ensures non-interactive bash (bash -c, bash script.sh)
          # sources NixOS environment. Without this, tools like runme that
          # spawn bash subprocesses won't have /run/current-system/sw/bin in PATH.
          BASH_ENV = "/etc/set-environment";
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
        }
        # Konductor self-hosting env (OVMF_CODE, OVMF_VARS, etc.)
        // (konductor.env pkgs)
      );
    };

    # =====================================================================
    # Systemd Configuration
    # =====================================================================
    systemd = {
      # Shared directory ownership with setgid
      # 2775 = setgid + rwxrwxr-x (new files inherit 'kc2' group)
      tmpfiles.rules = [
        "d /opt/konductor 2775 kc2 kc2 -"
        "d /home/Git 2775 kc2 kc2 -"
        "d /workspace 2775 kc2 kc2 -"
      ];

      network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          networkConfig.DHCP = "yes";
        };
        # Prevent systemd-networkd from managing Docker interfaces
        # Docker creates bridges (docker0, br-*) and veth pairs dynamically via netlink.
        # Without this, systemd-networkd may race with Docker's netlink operations,
        # causing veth interfaces to not be attached to bridges properly.
        # IMPORTANT: Must be "05-" to come BEFORE "10-ethernet" which matches Type=ether
        # (veth is type ether, so it would match 10-ethernet first otherwise)
        # See: BUG_REPORT.docker-compose-nixos-qcow2.md
        networks."05-docker-unmanaged" = {
          matchConfig.Name = "docker* br-* veth*";
          linkConfig = {
            Unmanaged = "yes";
            RequiredForOnline = "no";
          };
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
          path = with pkgs; [ util-linux coreutils ];
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
        # Konductor Provenance Verification Service
        # =====================================================================
        # Verifies build provenance on boot and outputs to:
        #   - journald (systemctl status konductor)
        #   - /run/konductor/motd (login MOTD)
        #   - /dev/ttyS0 (serial console for hypervisor capture)
        #
        # MOTD design: Informative for newcomers, unimposing for daily users
        #   Line 1: Identity (version, nix derivation, git commit)
        #   Line 2: Status + hint for more info
        konductor = {
          description = "Konductor Provenance Verification";
          after = [ "local-fs.target" "network.target" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ coreutils gnused git nix jq ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "konductor";
            ExecStart = pkgs.writeShellScript "konductor-verify" ''
              set -euo pipefail
              ERRORS=0
              MOTD_FILE="/run/konductor/motd"

              echo "=== Konductor Provenance ==="

              # Check provenance file exists
              if [ ! -f /.konductor ]; then
                echo "· provenance: /.konductor not found (pre-provisioned or build in progress)"
                {
                  echo ""
                  echo "  Konductor · Awaiting provenance"
                  echo "  · Run vm:provenance task or check /.konductor after build"
                  echo ""
                } > "$MOTD_FILE"
                # Don't fail - provenance is written after rebuild during build process
                exit 0
              fi
              echo "✓ provenance: /.konductor"

              # Parse provenance fields
              GIT_COMMIT=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)
              GIT_DIRTY=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' /.konductor)
              NIX_DRV=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' /.konductor)
              NIX_VERSION=$(sed -n 's/^nix_version = "\(.*\)"$/\1/p' /.konductor)
              BUILD_DATE=$(sed -n 's/^build_date = "\(.*\)"$/\1/p' /.konductor)

              # Output full provenance to journal
              cat /.konductor

              # Check git_dirty (trust gate)
              if [ "$GIT_DIRTY" != "0" ]; then
                echo "⚠ git_dirty=$GIT_DIRTY (built from dirty tree)"
              fi

              # If /opt/konductor/src exists, verify against it
              # Source is at /opt/konductor/src/ (bundled via git-bundle in Dockerfile.qcow2)
              VERIFIED=""
              if [ -d /opt/konductor/src ] && [ -d /opt/konductor/src/.git ]; then
                cd /opt/konductor/src

                # Verify git_commit
                EXPECTED="$GIT_COMMIT"
                ACTUAL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                if [ "$EXPECTED" = "$ACTUAL" ]; then
                  echo "✓ git_commit: ''${EXPECTED:0:12}"
                else
                  echo "✗ git_commit: expected ''${EXPECTED:0:12}, got ''${ACTUAL:0:12}"
                  ((ERRORS++)) || true
                fi

                # Verify flake_lock_sha256
                if [ -f flake.lock ]; then
                  EXPECTED=$(sed -n 's/^flake_lock_sha256 = "\(.*\)"$/\1/p' /.konductor)
                  ACTUAL=$(sha256sum flake.lock | cut -d' ' -f1)
                  if [ "$EXPECTED" = "$ACTUAL" ]; then
                    echo "✓ flake_lock: ''${EXPECTED:0:12}..."
                  else
                    echo "✗ flake_lock: mismatch"
                    ((ERRORS++)) || true
                  fi
                fi

                # Verify nix_drv (the key reproducibility check)
                EXPECTED="$NIX_DRV"
                if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "unknown" ]; then
                  ACTUAL=$(nix path-info --derivation .#qcow2 2>/dev/null | head -1 | xargs basename | cut -d- -f1 || echo "unknown")
                  if [ "$EXPECTED" = "$ACTUAL" ]; then
                    echo "✓ nix_drv: $EXPECTED (REPRODUCIBLE)"
                    VERIFIED="yes"
                  else
                    echo "✗ nix_drv: expected $EXPECTED, got $ACTUAL"
                    ((ERRORS++)) || true
                  fi
                fi
              else
                echo "· /opt/konductor not available for verification"
              fi

              # Build compact MOTD (2 lines, informative but unimposing)
              {
                echo ""
                # Line 1: Identity
                IDENTITY="  Konductor"
                [ -n "$NIX_DRV" ] && [ "$NIX_DRV" != "unknown" ] && IDENTITY="$IDENTITY · nix-''${NIX_DRV:0:12}"
                [ -n "$GIT_COMMIT" ] && [ "$GIT_COMMIT" != "unknown" ] && IDENTITY="$IDENTITY · git-''${GIT_COMMIT:0:7}"
                echo "$IDENTITY"

                # Line 2: Status + actionable hint
                if [ "$ERRORS" -eq 0 ]; then
                  if [ -n "$VERIFIED" ]; then
                    echo "  ✓ Verified · systemctl status konductor · cat /.konductor"
                  elif [ "$GIT_DIRTY" != "0" ]; then
                    echo "  ⚠ Dirty build · systemctl status konductor · cat /.konductor"
                  else
                    echo "  ✓ Provenance · systemctl status konductor · cat /.konductor"
                  fi
                else
                  echo "  ✗ $ERRORS error(s) · systemctl status konductor"
                fi
                echo ""
              } > "$MOTD_FILE"

              # Output to serial console
              {
                echo "=== Konductor Provenance ==="
                cat /.konductor
                if [ "$ERRORS" -eq 0 ]; then
                  echo "=== VERIFIED ==="
                else
                  echo "=== $ERRORS ERROR(S) ==="
                fi
              } > /dev/ttyS0 2>/dev/null || true

              # Final status
              if [ "$ERRORS" -eq 0 ]; then
                echo "=== VERIFIED ==="
                exit 0
              else
                echo "=== $ERRORS VERIFICATION ERROR(S) ==="
                exit 1
              fi
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

        # =====================================================================
        # CA Trust Configuration (Cloud-init Runtime)
        # =====================================================================
        # Creates CA bundle from cloud-init injected cluster CA certificate.
        # Cloud-init writes /etc/konductor/cluster-ca.crt, this service:
        #   1. Concatenates system CAs + cluster CA into ca-bundle.crt
        #   2. Creates drop-in for forgejo-runner with CA environment vars
        #
        # Usage: Cloud-init user-data writes cluster CA:
        #   write_files:
        #     - path: /etc/konductor/cluster-ca.crt
        #       content: |
        #         -----BEGIN CERTIFICATE-----
        #         <cluster-ca-certificate>
        #         -----END CERTIFICATE-----
        konductor-ca-setup = {
          description = "Configure CA trust from cloud-init cluster CA";
          before = [ "forgejo-runner.service" ];
          after = [ "cloud-init.service" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            ConditionPathExists = "/etc/konductor/cluster-ca.crt";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "setup-ca-trust" ''
              set -euo pipefail
              CLUSTER_CA="/etc/konductor/cluster-ca.crt"
              CA_BUNDLE="/etc/konductor/ca-bundle.crt"
              SYSTEM_CA="/etc/ssl/certs/ca-certificates.crt"
              DROPIN_DIR="/run/systemd/system/forgejo-runner.service.d"

              echo "Creating CA bundle from cluster CA"

              # Create konductor config directory
              mkdir -p /etc/konductor

              # Create CA bundle: system CAs + cluster CA
              if [ -f "$SYSTEM_CA" ]; then
                cat "$SYSTEM_CA" "$CLUSTER_CA" > "$CA_BUNDLE"
              else
                # Fallback if system CA bundle doesn't exist
                cp "$CLUSTER_CA" "$CA_BUNDLE"
              fi
              chmod 644 "$CA_BUNDLE"

              echo "Creating forgejo-runner CA environment drop-in"

              # Create drop-in directory for forgejo-runner
              mkdir -p "$DROPIN_DIR"

              # Create drop-in with CA environment variables
              cat > "$DROPIN_DIR/ca-bundle.conf" << EOF
              [Service]
              Environment="SSL_CERT_FILE=$CA_BUNDLE"
              Environment="REQUESTS_CA_BUNDLE=$CA_BUNDLE"
              Environment="GIT_SSL_CAINFO=$CA_BUNDLE"
              Environment="NIX_SSL_CERT_FILE=$CA_BUNDLE"
              Environment="CURL_CA_BUNDLE=$CA_BUNDLE"
              EOF

              # Reload systemd to pick up the drop-in
              systemctl daemon-reload

              echo "CA trust configured: $CA_BUNDLE"
            '';
          };
        };

        # =====================================================================
        # Forgejo Runner Service
        # =====================================================================
        # Runs Forgejo Actions runner daemon when registration is complete.
        # Registration creates .runner file; service only starts if it exists.
        #
        # Registration (shared secret pattern - idempotent):
        #   forgejo-runner create-runner-file \
        #     --secret <40-char-hex> \
        #     --instance <forgejo-url> \
        #     --name <hostname> \
        #     --connect
        #
        # The .runner file is created in /home/runner/.config/forgejo-runner/
        # CA trust is configured by konductor-ca-setup service (drop-in).
        forgejo-runner = {
          description = "Forgejo Actions Runner";
          after = [
            "network-online.target"
            "docker.service"
            "konductor-ca-setup.service"
          ];
          wants = [
            "network-online.target"
            "docker.service"
          ];
          requires = [ "konductor-ca-setup.service" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            # Only start if runner is registered (.runner file exists)
            ConditionPathExists = "/home/runner/.config/forgejo-runner/.runner";
          };
          serviceConfig = {
            Type = "simple";
            User = "runner";
            Group = "users";
            WorkingDirectory = "/home/runner";
            Environment = [
              "HOME=/home/runner"
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
              "DOCKER_HOST=unix:///var/run/docker.sock"
              # OVMF EFI firmware for QEMU (required for QCOW2 builds)
              "OVMF_CODE=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
              "OVMF_VARS=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd"
              # Build tools
              "DOCKER_BUILDKIT=1"
              # CI marker
              "CI=true"
            ];
            ExecStart = "${programs.forgejo.runner}/bin/forgejo-runner daemon --config /home/runner/.config/forgejo-runner/config.yaml";
            Restart = "always";
            RestartSec = 10;
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

      # =====================================================================
      # DNS Resolution (systemd-resolved)
      # =====================================================================
      # Enables systemd-resolved for DNS resolution.
      # Per-link DNS routing for docker.arpa is configured by mise task
      # `dev:k8s:network:create` when docker-dev bridge is created.
      # See: .config/mise/toml/talos.compose.toml
      resolved = {
        enable = true;
        # Use Google/Cloudflare as fallback DNS
        fallbackDns = [ "8.8.8.8" "1.1.1.1" ];
        # DNSSEC causes issues with private zones, disable it
        dnssec = "false";
      };

      # Cloud-init for dynamic configuration
      cloud-init = {
        enable = true;
        network.enable = true;
        settings = {
          # Configure NixOS distro helper paths
          system_info = {
            distro = "nixos";
            paths = {
              cloud_dir = "/var/lib/cloud";
              run_dir = "/run/cloud-init";
            };
          };
        };
      };

      # Spice/QEMU guest tools for clipboard, display, etc.
      spice-vdagentd.enable = true;
    };

    # Fix cloud-init helper tool path for keys-to-console module
    # Cloud-init expects helper at /usr/libexec/cloud-init/write-ssh-key-fingerprints
    # but NixOS has it at ${pkgs.cloud-init}/libexec/write-ssh-key-fingerprints
    environment.etc."libexec/cloud-init/write-ssh-key-fingerprints".source =
      "${pkgs.cloud-init}/libexec/write-ssh-key-fingerprints";

    # =====================================================================
    # Virtualisation Configuration
    # =====================================================================
    virtualisation = {
      # Disk size for VM - increased to accommodate full package set
      diskSize = lib.mkDefault (30 * 1024); # 30GB (full konductor environment)

      # Docker - installed but not started on boot
      # Start via: systemctl start docker
      docker = {
        enable = true;
        enableOnBoot = false;

        # Explicit storage driver (don't rely on auto-detection)
        storageDriver = "overlay2";

        # Journald for log aggregation (NixOS default, explicit for clarity)
        logDriver = "journald";

        daemon.settings = {
          # Networking: explicit control for systemd-networkd coexistence
          iptables = true;
          ip-forward = true;
          ip-masq = true;
          userland-proxy = false;
          icc = true;

          # Live restore: reduces veth churn, helps with systemd-networkd
          live-restore = true;

          # Explicit address pool - uses 172.20.0.0/16 to avoid conflicts with:
          # - 10.5.0.0/24: Cilium L2 LoadBalancer pool (host docker-dev bridge)
          # - 10.0.2.0/24: KubeVirt pod network (masquerade)
          # - 10.96.0.0/12: Kubernetes service CIDR
          # - 10.244.0.0/16: Kubernetes pod CIDR
          # - 172.17.0.0/16: Default Docker bridge
          default-address-pools = [
            { base = "172.20.0.0/16"; size = 24; }
          ];
        };

        # Auto-prune for CI/CD runners (prevents disk exhaustion)
        autoPrune = {
          enable = true;
          dates = "daily";
          flags = [ "--all" "--volumes" ];
        };
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
      # Bootloader Configuration (EFI)
      # =====================================================================
      # Required for nixosConfigurations (nixos-rebuild on running VMs).
      # The qcow-efi format provides this automatically for image builds,
      # but nixpkgs.lib.nixosSystem needs explicit bootloader config.
      loader = {
        grub = {
          enable = true;
          device = "nodev";  # EFI doesn't use a specific device
          efiSupport = true;
          efiInstallAsRemovable = true;  # Works without NVRAM variables
        };
        efi = {
          canTouchEfiVariables = false;  # Don't modify NVRAM (safer for VMs)
          efiSysMountPoint = "/boot";
        };
      };

      # =====================================================================
      # Storage Optimization for Ceph RBD Block Devices
      # =====================================================================
      # Aligned for 4KB Ceph BlueStore allocation (bluestore_min_alloc_size_ssd)
      # See: Pulumi.optiplex-rook-ceph.yaml ceph_config_override

      # I/O scheduler: none for virtio-blk (Ceph handles its own scheduling)
      # Serial console for hypervisor log capture (KubeVirt, libvirt)
      kernelParams = [
        "console=tty0"
        "console=ttyS0,115200"
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

    # =====================================================================
    # Filesystem Configuration
    # =====================================================================
    # Required for nixosConfigurations (nixos-rebuild on running VMs).
    # Uses labels set by qcow-efi format during image creation.
    # Options optimized for Ceph RBD block devices.
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      options = [
        "noatime"     # Reduce metadata writes
        "nodiratime"  # Reduce directory access time updates
        "discard"     # TRIM/unmap for thin provisioning
        "commit=60"   # Increase journal commit interval (seconds)
      ];
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };

    # =====================================================================
    # Host Nix Store Overlay (Build Acceleration)
    # =====================================================================
    # During QCOW2 build, the host's /nix/store is mounted via 9p virtfs.
    # An overlay filesystem makes it writable while using host paths as cache.
    # In production (no host mount), these mounts fail gracefully (nofail).
    #
    # Architecture:
    #   /nix/.host-store (9p, ro) ─┐
    #                              ├─► overlay ─► /nix/store (rw)
    #   /nix/.rw-store (tmpfs)  ───┘
    #
    # This reduces build time by avoiding re-download of paths that exist
    # on the build host. New/modified paths go to the tmpfs upper layer.

    # Mount host's nix store read-only via 9p (only during build)
    # Uses automount to avoid "failed" status when virtfs device doesn't exist
    # The mount only triggers when /nix/.host-store is accessed
    fileSystems."/nix/.host-store" = {
      device = "nixstore";
      fsType = "9p";
      options = [
        "trans=virtio"
        "version=9p2000.L"
        "cache=loose"      # Aggressive caching for read-only mount
        "ro"
        "nofail"           # Don't fail boot if not available (production)
        "noauto"           # Don't mount at boot (prevents failed unit)
        "x-systemd.automount"  # Mount on access
        "x-systemd.idle-timeout=60"  # Unmount after 60s idle
        "x-systemd.device-timeout=5s"
      ];
      neededForBoot = false;  # Not required - graceful degradation
    };

    # Writable layer for overlay (tmpfs during build)
    fileSystems."/nix/.rw-store" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "mode=0755"
        "size=20G"         # Upper layer for new builds
        "nofail"
      ];
      neededForBoot = false;
    };

    # Systemd service to set up nix store overlay when host store is available
    # This runs early in boot, before nix-daemon, and only activates during
    # QCOW2 build when the host's /nix/store is mounted via 9p virtfs.
    # Note: No ConditionPathIsMountPoint since we use automount - the script
    # checks availability by accessing the path (triggering automount if device exists)
    systemd.services.nix-store-overlay = {
      description = "Set up Nix store overlay with host cache";
      wantedBy = [ "nix-daemon.service" ];
      before = [ "nix-daemon.service" ];
      after = [ "local-fs.target" "nix-.host\\x2dstore.automount" ];
      unitConfig = {
        DefaultDependencies = false;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nix-store-overlay-setup" ''
          set -euo pipefail

          # Verify host store has content
          if [ ! -d /nix/.host-store ] || [ -z "$(ls -A /nix/.host-store 2>/dev/null)" ]; then
            echo "Host store not available or empty, using local store"
            exit 0
          fi

          # Create overlay directories
          mkdir -p /nix/.rw-store/upper /nix/.rw-store/work

          # Check if already mounted as overlay
          if mount | grep -q "overlay on /nix/store"; then
            echo "Overlay already mounted"
            exit 0
          fi

          # Bind mount original store to preserve it
          if [ ! -d /nix/.local-store ]; then
            mkdir -p /nix/.local-store
            mount --bind /nix/store /nix/.local-store
          fi

          # Mount overlay: host store (ro) + rw-store (rw) -> /nix/store
          mount -t overlay overlay \
            -o lowerdir=/nix/.host-store:/nix/.local-store,upperdir=/nix/.rw-store/upper,workdir=/nix/.rw-store/work \
            /nix/store

          echo "Nix store overlay activated with host cache"
        '';
        ExecStop = pkgs.writeShellScript "nix-store-overlay-teardown" ''
          # Unmount overlay and restore local store
          if mount | grep -q "overlay on /nix/store"; then
            umount /nix/store || true
            if [ -d /nix/.local-store ]; then
              mount --bind /nix/.local-store /nix/store || true
              umount /nix/.local-store || true
            fi
          fi
        '';
      };
    };

    # Nix configuration
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        auto-optimise-store = true;
        accept-flake-config = true;
        trusted-users = [
          "root"
          "@wheel"
        ];
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
      # Pre-configured flake registry - local source for zero network dependency
      # The bundled /opt/konductor/src has the full Nix store cache from build
      # This enables offline operation and provenance-attested builds
      registry.konductor = {
        from = {
          type = "indirect";
          id = "konductor";
        };
        to = {
          type = "path";
          path = "/opt/konductor/src";
        };
      };
    };
  };

in
{
  # Export the module for nixosConfigurations (live rebuilds)
  inherit konductorModule;

  # QCOW2 VM image
  # Use qcow-efi for proper 4K partition alignment (ESP starts at 8MiB)
  # The "qcow" format uses hybrid partition table with BIOS partition at sector 0,
  # which causes alignment warnings and suboptimal I/O on Ceph RBD.
  image = nixos-generators.nixosGenerate {
    inherit system;
    format = "qcow-efi";
    # Note: copyChannel is not exposed by nixos-generators wrapper
    # Channel copy prevented via installer.cloneConfig = false below
    modules = [ konductorModule ];
  };
}
