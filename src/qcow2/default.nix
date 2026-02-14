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

  # Catppuccin theme sources from catppuccin/nix flake
  catppuccinSources = inputs.catppuccin.packages.${system};

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions catppuccinSources; };

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

  # Pre-installed VS Code extensions for code-server
  # Symlinked into each user's extensions dir at service start
  vscodeExtensionsList = with pkgs.vscode-extensions; [
    # Theme
    catppuccin.catppuccin-vsc            # Catppuccin theme (default)
    catppuccin.catppuccin-vsc-icons      # Catppuccin file icons

    # Language support — Python
    ms-python.python                     # Python language server + debugging
    ms-python.vscode-pylance             # Pylance type checker
    ms-python.debugpy                    # Python debugger
    charliermarsh.ruff                   # Ruff linter/formatter

    # Language support — Go
    golang.go                            # Go language server (gopls)

    # Language support — Rust
    rust-lang.rust-analyzer              # Rust analyzer

    # Language support — JavaScript/TypeScript
    dbaeumer.vscode-eslint               # ESLint integration

    # Language support — Nix
    jnoortheen.nix-ide                   # Nix language support
    mkhl.direnv                          # direnv integration

    # Language support — Shell
    timonwong.shellcheck                 # ShellCheck linter
    foxundermoon.shell-format            # Shell script formatter

    # Config file support
    redhat.vscode-yaml                   # YAML language server
    tamasfe.even-better-toml             # TOML language server
    ms-azuretools.vscode-docker          # Dockerfile + Compose

    # Editor tools
    editorconfig.editorconfig            # EditorConfig support
    esbenp.prettier-vscode               # Prettier formatter
    christian-kohler.path-intellisense   # Path autocompletion
    gruntfuggly.todo-tree                # TODO/FIXME tree view
    usernamehw.errorlens                 # Inline error/warning display
    vscodevim.vim                        # Vim keybindings
    streetsidesoftware.code-spell-checker # Spell checking
    alefragnani.bookmarks                # Bookmarkable lines
    formulahendry.auto-rename-tag        # Auto-rename paired HTML/XML tags

    # Markdown
    bierner.github-markdown-preview      # GitHub-flavored markdown preview
    bierner.markdown-mermaid             # Mermaid diagram support
    davidanson.vscode-markdownlint       # Markdown linting
    yzhang.markdown-all-in-one           # Markdown TOC, preview, shortcuts

    # Remote development
    ms-vscode-remote.remote-ssh          # SSH into remote hosts
    ms-vscode-remote.remote-ssh-edit     # Edit SSH config
    ms-vscode-remote.remote-containers   # Dev containers support
    ms-vscode.remote-explorer            # Remote explorer UI

    # Infrastructure
    ms-kubernetes-tools.vscode-kubernetes-tools  # Kubernetes cluster management

    # Nix (additional)
    bbenoist.nix                          # Nix syntax highlighting
    arrterian.nix-env-selector           # Nix environment selector

    # Debugging
    vadimcn.vscode-lldb                  # LLDB debugger (Rust/C/C++)

    # Collaboration
    ms-vsliveshare.vsliveshare           # Live Share real-time collaboration

    # Git & GitHub
    eamodio.gitlens                      # Git blame, history, annotations
    mhutchie.git-graph                   # Git commit graph visualization
    github.vscode-github-actions         # GitHub Actions workflow support
    github.vscode-pull-request-github    # GitHub PR and issue integration

    # AI
    github.copilot                       # GitHub Copilot
    github.copilot-chat                  # GitHub Copilot Chat
  ] ++ [
    # Extensions not in nixpkgs or with stale nixpkgs hashes — fetched from VS Code Marketplace
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "claude-code";
      publisher = "anthropic";
      version = "2.0.50";
      sha256 = "sha256-Pd4rRLS613/zSn8Pvr/cozaIAqrG06lmUC6IxHm97XQ=";
    })
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "runme";
      publisher = "stateful";
      version = "3.16.1";
      sha256 = "sha256-o7wYCCnVGzUDNr2Lb+ovbifn/Zq7IU/jZUPQJVeFPeI=";
    })
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "mise-vscode";
      publisher = "hverlin";
      version = "1.3.0";
      sha256 = "sha256-uYpc2+eXmIAqOOviywitAUxXLc6+cZl/CdeoBZsW5C8=";
    })
    # GitHub Local Actions
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "github-local-actions";
      publisher = "sanjulaganepola";
      version = "1.2.5";
      sha256 = "sha256-gc3iOB/ibu4YBRdeyE6nmG72RbAsV0WIhiD8x2HNCfY=";
    })
    # TODO highlight
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "vscode-todo-highlight";
      publisher = "wayou";
      version = "1.0.5";
      sha256 = "sha256-CQVtMdt/fZcNIbH/KybJixnLqCsz5iF1U0k+GfL65Ok=";
    })
    # Python environment selector
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "vscode-python-envs";
      publisher = "ms-python";
      version = "1.16.0";
      sha256 = "sha256-81bFme63+UHrti1JWU8jlfj79k9bFVyqnY0SyaVO6Dc=";
    })
    # Pulumi IaC
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "pulumi-lsp-client";
      publisher = "pulumi";
      version = "0.3.2024091924";
      sha256 = "sha256-yWQY5/JpOKw4gerzy04er39Qsc87qnSz4C1tDC34BLw=";
    })
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "pulumi-vscode-tools";
      publisher = "pulumi";
      version = "0.4.0";
      sha256 = "sha256-VthowmmNENCcJGiFQpORGoVDMVAZX4k1f8YkFB7cD0c=";
    })
    (pkgs.vscode-utils.extensionFromVscodeMarketplace {
      name = "pulumi-vscode-copilot";
      publisher = "pulumi";
      version = "0.3.4";
      sha256 = "sha256-2XLSTlkPMj+z6WL/CCEaFnU1trYZqYcPrODg+S67gcE=";
    })
  ];

  # Combined extensions directory: /nix/store/...-vscode-extensions/share/vscode/extensions/
  vscodeExtensionsDir = pkgs.symlinkJoin {
    name = "vscode-extensions";
    paths = vscodeExtensionsList;
  };

  # Default VS Code settings (copied to user dir on first start, user can modify)
  vscodeDefaultSettings = pkgs.writeText "vscode-settings.json" (builtins.toJSON {
    # Window
    "window.title" = "\${dirty}\${activeEditorShort}\${separator}\${rootName}";

    # Theme
    "workbench.colorTheme" = "Catppuccin Frappé";
    "workbench.iconTheme" = "catppuccin-frappe";

    # Terminal
    "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
    "terminal.integrated.fontSize" = 14;
    "terminal.integrated.defaultProfile.linux" = "bash";
    "terminal.integrated.profiles.linux" = {
      bash = { path = "/bin/bash"; args = ["-l"]; };
    };

    # Editor
    "editor.fontFamily" = "JetBrainsMono Nerd Font, monospace";
    "editor.fontSize" = 14;
    "editor.lineNumbers" = "relative";
    "editor.formatOnSave" = true;
    "editor.formatOnPaste" = true;
    "editor.rulers" = [80 120];
    "editor.bracketPairColorization.enabled" = true;
    "editor.guides.bracketPairs" = true;

    # Files
    "files.trimTrailingWhitespace" = true;
    "files.insertFinalNewline" = true;

    # Git
    "git.ignoreLimitWarning" = true;
    "github.gitAuthentication" = true;

    # Go
    "go.toolsManagement.checkForUpdates" = "off";
    "go.useLanguageServer" = true;

    # Rust
    "rust-analyzer.check.command" = "clippy";

    # Nix
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nixd";

    # direnv
    "direnv.restart.automatic" = true;
  });

  # PKI module for VM identity and certificate chain of trust
  pkiModule = import ../modules/pki.nix;

  # Certificate precedence detection script (Tier 1 → 2 → 3 fallback)
  certPrecedenceScript = import ../lib/cert-precedence.nix { inherit pkgs; };

  # Common home-manager configuration for built-in users
  # Provisions shell configs (.bashrc, .bash_profile, etc.) at build time
  # Uses canonical config from src/config/shell/ (SSOT)
  homeManagerUserConfig = {
    home.file.".bashrc".text = config.shell.bash.bashrcContent;
    home.file.".bash_profile".text = shellContent.bashProfileContent;
    home.file.".inputrc".text = shellContent.inputrcContent;
    home.file.".config/starship.toml".text = config.shell.starship.configContent;
    home.file.".config/atuin/config.toml" = {
      text = config.shell.atuin.configContent;
      force = true;  # Overwrite existing atuin config
    };
    home.file.".envrc".text = ''
      # Konductor VM - all packages pre-installed system-wide
      # This .envrc is for project-specific env vars only
      dotenv_if_exists .env
      dotenv_if_exists "$HOME/.env"
    '';
    home.stateVersion = versions.nixos.stateVersion;
  };

  # Service template generator for konductor multi-user services
  # Reduces code duplication by abstracting common patterns:
  # - Dynamic firewall management (ExecStartPre opens port, ExecStopPost closes)
  # - Certificate precedence detection (Tier 1→2→3 fallback)
  # - RuntimeDirectory for /run/konductor state
  # - EnvironmentFile pattern for PORT and cert variables
  mkKonductorService = {
    serviceName,     # Service name (ttyd, vscode, restty, ghostty)
    basePort,        # Base port for port calculation (e.g., 8000 for vscode)
    afterServices ? [ "network.target" "konductor-init.service" "konductor-pki.service" ],
    documentation ? [],
    workingDirectory ? "/workspace",
    extraServiceConfig ? {},  # Additional serviceConfig options
  }: {
    "konductor-${serviceName}@" = {
      description = "Konductor ${lib.toUpper (builtins.substring 0 1 serviceName)}${builtins.substring 1 (builtins.stringLength serviceName) serviceName} for %i";
      inherit documentation;
      after = afterServices;

      serviceConfig = {
        Type = "simple";
        User = "%i";
        Group = "users";
        WorkingDirectory = workingDirectory;

        # RuntimeDirectory creates /run/konductor with proper permissions
        # Automatically cleaned up when last service stops
        RuntimeDirectory = "konductor";

        ExecStartPre = [
          # Step 1: Find best available certificate (Tier 1→2→3)
          # Writes CERT_PATH, KEY_PATH, CERT_TIER to /run/konductor/konductor-SERVICE@USER.cert-env
          # Exits non-zero if no valid cert found (prevents service start)
          "+${pkgs.writeShellScript "find-cert-${serviceName}" ''
            set -euo pipefail

            # Run precedence check
            if ! CERT_INFO=$(${certPrecedenceScript}/bin/konductor-find-best-cert); then
              echo "FATAL: No valid certificate available for konductor-${serviceName}@%i" >&2
              exit 1
            fi

            # Write cert info to runtime env file
            echo "$CERT_INFO" > /run/konductor/konductor-${serviceName}@%i.cert-env

            # Log which cert tier was selected
            TIER=$(echo "$CERT_INFO" | ${pkgs.gnugrep}/bin/grep CERT_TIER | ${pkgs.coreutils}/bin/cut -d= -f2)
            echo "✓ Using certificate tier: $TIER"
          ''}"

          # Step 2: Open firewall port
          # PORT variable from EnvironmentFile (written by konductor-init.service)
          ''+${pkgs.nftables}/bin/nft add rule inet nixos-fw input-allow tcp dport ''${PORT} accept comment "konductor-${serviceName}@%i-port''${PORT}"''
        ];

        # Environment files (merged at runtime)
        # EnvironmentFile variables are expanded in ExecStart
        EnvironmentFile = [
          "/var/lib/konductor/env/konductor-${serviceName}@%i.env"  # PORT, USER_UID
          "/run/konductor/konductor-${serviceName}@%i.cert-env"     # CERT_PATH, KEY_PATH, CERT_TIER
        ];

        # Placeholder ExecStart - konductor-init.service drop-in overrides with actual command
        # Using /usr/bin/false ensures service fails if drop-in not generated (fail-safe)
        ExecStart = "${pkgs.coreutils}/bin/false";

        # Close firewall port on stop
        # Parse nftables output to find rule handle by comment, then delete by handle
        ExecStopPost = pkgs.writeShellScript "cleanup-firewall-${serviceName}" ''
          HANDLE=$(${pkgs.nftables}/bin/nft --handle list chain inet nixos-fw input-allow | \
            ${pkgs.gnugrep}/bin/grep "comment \"konductor-${serviceName}@%i-port''${PORT}\"" | \
            ${pkgs.gnugrep}/bin/grep -o "handle [0-9]*" | \
            ${pkgs.gawk}/bin/awk '{print $2}')
          if [ -n "$HANDLE" ]; then
            ${pkgs.nftables}/bin/nft delete rule inet nixos-fw input-allow handle $HANDLE
          fi
        '';

        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
      } // extraServiceConfig;
    };
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

    # =====================================================================
    # /etc Overlay Filesystem (Runtime Mutability)
    # =====================================================================
    # Enable overlay filesystem for /etc to allow runtime modifications.
    # This is REQUIRED for cloud-init to write to /etc/hosts at deploy time
    # for static host entries (e.g., proxy hostname bootstrap before DNS).
    #
    # With mutable overlay (the default when enabled):
    # - cloud-init can append to /etc/hosts via runcmd
    # - Modifications persist in /.rw-etc/upper
    # - Changes survive reboots but NOT nixos-rebuild
    #
    # Requires kernel >= 6.6 (we use linuxPackages_latest)
    # See: https://nixos.wiki/wiki/Etc_overlay
    system.etc.overlay.enable = true;
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
          # Multi-user web service ports (7000-10499) are dynamically managed
          # by systemd service templates (konductor-{ttyd,vscode,restty,ghostty}@)
          # via ExecStartPre/ExecStopPost nftables rules
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

      # Hypervisor CA paths (mounted from parent cluster at /mnt/pki)
      # Vertical PKI: parent cluster CA signs VM wildcard cert
      hypervisorCaPath = "/mnt/pki/ca.crt";
      hypervisorKeyPath = "/mnt/pki/tls.key";
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
        # Atuin shell history (config + bash-preexec for hooks)
        ATUIN_CONFIG_DIR = config.shell.atuin.env.ATUIN_CONFIG_DIR;
        KONDUCTOR_PREEXEC_PATH = config.shell.atuin.env.KONDUCTOR_PREEXEC_PATH;
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
      # Uses canonical config from src/config/shell/ (SSOT)
      etc = {
        "skel/.bashrc".text = config.shell.bash.bashrcContent;
        "skel/.bash_profile".text = shellContent.bashProfileContent;
        "skel/.inputrc".text = shellContent.inputrcContent;
        # Note: .gitconfig is NOT in skel - git config is at system level via programs.git
        "skel/.config/starship.toml".text = config.shell.starship.configContent;
        "skel/.config/atuin/config.toml".text = config.shell.atuin.configContent;

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

          # Python: activate SSOT venv from UV_PROJECT_ENVIRONMENT (set in .envrc/.env.example)
          if [ -n "$UV_PROJECT_ENVIRONMENT" ] && [ -d "$UV_PROJECT_ENVIRONMENT" ]; then
            source "$UV_PROJECT_ENVIRONMENT/bin/activate" 2>/dev/null || true
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
        # Web terminal (ttyd with Catppuccin theme)
        ++ programs.ttyd.packages
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
          # Multi-user service infrastructure
          yj           # TOML to JSON converter (for konductor-init.service)
          yq-go        # YAML/TOML/JSON processor
        ])
        # Certificate precedence detection for multi-user services
        ++ [ certPrecedenceScript ]
        ++ (with pkgs; [
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
        # Tmux configuration paths (for config reload and help)
        // programs.tmux.env
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

        # Mask libvirt-guests - it tries to suspend/resume guests but libvirtd isn't auto-started
        # wantedBy=[] only prevents auto-start; enable=false masks it completely (symlink to /dev/null)
        "libvirt-guests".enable = false;

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
          description = "Konductor Validation Gate";
          after = [
            "cloud-init.service"
            "local-fs.target"
            "network.target"
            "konductor-pki-bundle.service"
          ];
          wants = [ "konductor-pki-bundle.service" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ coreutils gnused git nix jq findutils gnugrep util-linux ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "konductor";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
            ExecStart = pkgs.writeShellScript "konductor-verify" ''
              set -euo pipefail
              ERRORS=0
              WARNINGS=0
              MOTD_FILE="/run/konductor/motd"

              # ═══════════════════════════════════════════════════════════════════
              # Read strict mode from /.konductor (default: false)
              # ═══════════════════════════════════════════════════════════════════
              STRICT="''${KONDUCTOR_STRICT:-false}"
              if [ -f "/.konductor" ]; then
                STRICT=$(sed -n 's/^strict = \(.*\)$/\1/p' /.konductor || echo "false")
              fi

              echo "═══════════════════════════════════════════════════════════════════════════════"
              echo "                         KONDUCTOR VALIDATION"
              echo "═══════════════════════════════════════════════════════════════════════════════"

              # ─────────────────────────────────────────────────────────────────────
              # PROVENANCE CHECK
              # ─────────────────────────────────────────────────────────────────────
              echo "┌─ PROVENANCE ────────────────────────────────────────────────────────────────┐"

              if [ ! -f /.konductor ]; then
                echo "  · provenance: /.konductor not found (pre-provisioned or build in progress)"
                {
                  echo ""
                  echo "  Konductor · Awaiting provenance"
                  echo "  · Run vm:provenance task or check /.konductor after build"
                  echo ""
                } > "$MOTD_FILE"
                echo "└─────────────────────────────────────────────────────────────────────────────┘"
                exit 0
              fi

              # Parse provenance fields
              GIT_COMMIT=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)
              GIT_DIRTY=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' /.konductor)
              NIX_DRV=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' /.konductor)

              echo "  ✓ provenance: /.konductor"
              [ -n "$GIT_COMMIT" ] && echo "  ✓ git_commit: $GIT_COMMIT"
              [ -n "$NIX_DRV" ] && echo "  ✓ nix_drv: $NIX_DRV"

              if [ "$GIT_DIRTY" != "0" ]; then
                echo "  ⚠ git_dirty: $GIT_DIRTY (built from dirty tree)"
                ((WARNINGS++)) || true
              fi

              # Verify against bundled source if available
              if [ -d /opt/konductor/src ] && [ -d /opt/konductor/src/.git ]; then
                cd /opt/konductor/src
                ACTUAL_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                if [ "$GIT_COMMIT" != "$ACTUAL_COMMIT" ]; then
                  echo "  ✗ git_commit mismatch: expected $GIT_COMMIT, got $ACTUAL_COMMIT"
                  ((ERRORS++)) || true
                fi

                if [ -f flake.lock ]; then
                  EXPECTED_LOCK=$(sed -n 's/^flake_lock_sha256 = "\(.*\)"$/\1/p' /.konductor)
                  ACTUAL_LOCK=$(sha256sum flake.lock | cut -d' ' -f1)
                  if [ "$EXPECTED_LOCK" != "$ACTUAL_LOCK" ]; then
                    echo "  ✗ flake_lock mismatch"
                    ((ERRORS++)) || true
                  else
                    echo "  ✓ flake_lock: $EXPECTED_LOCK"
                  fi
                fi
                cd /
              fi
              echo "└─────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # SGX EPC CHECK (Hardware Root of Trust)
              # ─────────────────────────────────────────────────────────────────────
              echo "┌─ SECURITY ──────────────────────────────────────────────────────────────────┐"

              EPC_COUNT=0
              # Check for SGX EPC sections in sysfs
              if [ -d /sys/devices/system/node ]; then
                EPC_COUNT=$(find /sys/devices/system/node -name "sgx_epc*" -type d 2>/dev/null | wc -l) || true
              fi
              # Fallback: check dmesg for SGX initialization
              if [ "$EPC_COUNT" -eq 0 ]; then
                if dmesg 2>/dev/null | grep -q "sgx: EPC section"; then
                  EPC_COUNT=$(dmesg 2>/dev/null | grep -c "sgx: EPC section") || true
                fi
              fi

              if [ "$EPC_COUNT" -gt 0 ]; then
                echo "  ✓ sgx: $EPC_COUNT EPC sections available"
                echo "  ✓ hardware root of trust: AVAILABLE"
              else
                if [ "$STRICT" = "true" ]; then
                  echo "  ✗ sgx: NO EPC SECTIONS AVAILABLE"
                  echo "  ✗ hardware root of trust: UNAVAILABLE"
                  ((ERRORS++)) || true
                else
                  echo "  ⚠ sgx: NO EPC SECTIONS AVAILABLE"
                  echo "  ⚠ hardware root of trust: UNAVAILABLE"
                  ((WARNINGS++)) || true
                fi
              fi
              echo "└─────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # STORAGE CHECK (Workspace Integrity)
              # ─────────────────────────────────────────────────────────────────────
              echo "┌─ STORAGE ───────────────────────────────────────────────────────────────────┐"

              if [ -d /workspace ]; then
                WS_GROUP=$(stat -c '%G' /workspace 2>/dev/null || echo "unknown")
                WS_MODE=$(stat -c '%a' /workspace 2>/dev/null || echo "000")

                if [ "$WS_GROUP" = "kc2" ]; then
                  echo "  ✓ /workspace group: $WS_GROUP"
                else
                  echo "  ✗ /workspace group: $WS_GROUP (expected kc2)"
                  ((ERRORS++)) || true
                fi

                # Check for setgid bit (2xxx)
                if [[ "$WS_MODE" =~ ^2[0-7]{3}$ ]] || [ "$WS_MODE" = "2775" ]; then
                  echo "  ✓ /workspace mode: $WS_MODE (setgid)"
                elif [ "$WS_MODE" = "775" ]; then
                  echo "  ⚠ /workspace mode: $WS_MODE (expected 2775 setgid)"
                  ((WARNINGS++)) || true
                else
                  echo "  ✗ /workspace mode: $WS_MODE (expected 2775)"
                  ((ERRORS++)) || true
                fi
              else
                echo "  · /workspace: not mounted"
              fi
              echo "└─────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # PKI STATUS
              # ─────────────────────────────────────────────────────────────────────
              echo "┌─ PKI ────────────────────────────────────────────────────────────────────────┐"
              if [ -f /etc/konductor/pki/vm/ca.crt ]; then
                PYTHONPATH=/opt/konductor/src/src ${pkgs.python3.withPackages (ps: [ps.cryptography])}/bin/python3 -m pki status 2>/dev/null || echo "  · pki status: failed to run"
              else
                echo "  · pki: certificates not yet generated"
              fi
              echo "└─────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # DETERMINE EXIT STATUS
              # ─────────────────────────────────────────────────────────────────────
              IDENTITY="Konductor"
              [ -n "$NIX_DRV" ] && IDENTITY="$IDENTITY · nix-''${NIX_DRV}"
              [ -n "$GIT_COMMIT" ] && IDENTITY="$IDENTITY · git-''${GIT_COMMIT}"

              if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
                # All checks passed
                echo "═══════════════════════════════════════════════════════════════════════════════"
                echo "                    ✓ VERIFIED (strict=$STRICT)"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                {
                  echo ""
                  echo "  $IDENTITY"
                  echo "  ✓ Verified · systemctl status konductor · cat /.konductor"
                  echo ""
                } > "$MOTD_FILE"
                # Output to serial console
                {
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                  echo "                    ✓ VERIFIED (strict=$STRICT)"
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                } > /dev/ttyS0 2>/dev/null || true
                exit 0

              elif [ "$ERRORS" -gt 0 ] && [ "$STRICT" = "true" ]; then
                # Errors in strict mode - BLOCK
                echo "═══════════════════════════════════════════════════════════════════════════════"
                echo "  FATAL: strict=true requires ALL validations to pass"
                echo "  BLOCKING: Dependent services will not start"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                echo "                    ✗ FAILED (strict=true)"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                {
                  echo ""
                  echo "  $IDENTITY"
                  echo "  ✗ FAILED ($ERRORS errors) · systemctl status konductor"
                  echo ""
                } > "$MOTD_FILE"
                # Output to serial console
                {
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                  echo "                    ✗ FAILED (strict=true)"
                  echo "  $ERRORS error(s) - forgejo-runner will NOT start"
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                } > /dev/ttyS0 2>/dev/null || true
                exit 1

              else
                # Warnings or errors in non-strict mode - DEGRADED
                echo "═══════════════════════════════════════════════════════════════════════════════"
                echo "  WARNING: Running in DEGRADED MODE (strict=$STRICT)"
                echo "  Dependent services will start but results should not merge to main"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                echo "                    ⚠ DEGRADED (strict=$STRICT)"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                {
                  echo ""
                  echo "  $IDENTITY"
                  echo "  ⚠ Degraded ($WARNINGS warnings, $ERRORS errors) · systemctl status konductor"
                  echo ""
                } > "$MOTD_FILE"
                # Output to serial console
                {
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                  echo "                    ⚠ DEGRADED (strict=$STRICT)"
                  echo "  $WARNINGS warning(s), $ERRORS error(s) - forgejo-runner will start"
                  echo "═══════════════════════════════════════════════════════════════════════════════"
                } > /dev/ttyS0 2>/dev/null || true
                exit 0
              fi
            '';
          };
        };

        # =====================================================================
        # Proxy Configuration (Cloud-init Runtime)
        # =====================================================================
        # Applies proxy settings from cloud-init to system services.
        # Cloud-init writes /etc/konductor/proxy.env, this service creates
        # systemd drop-ins for services that need proxy configuration:
        #   - nix-daemon: For nix builds and cache fetches
        #   - docker: For pulling container images
        #
        # CRITICAL ORDERING:
        #   - MUST run AFTER cloud-init.service (when write_files completes)
        #   - MUST run BEFORE nix-daemon/docker to configure them on first boot
        #   - Explicitly restarts services to handle case where they started early
        #
        # Usage: Cloud-init user-data (or Pulumi KonductorProxySpec) writes:
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
          description = "Configure proxy for system services from cloud-init";
          # Wait for cloud-init to complete (when proxy.env is written)
          after = [ "cloud-init.service" ];
          # Start before these services (for ordering on subsequent boots)
          before = [ "nix-daemon.service" "docker.service" ];
          # Activate via multi-user target (not wantedBy the services themselves)
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            ConditionPathExists = "/etc/konductor/proxy.env";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "setup-system-proxy" ''
              set -euo pipefail
              PROXY_ENV="/etc/konductor/proxy.env"

              echo "Configuring system proxy from $PROXY_ENV"

              # Configure nix-daemon proxy
              NIX_DROPIN_DIR="/run/systemd/system/nix-daemon.service.d"
              mkdir -p "$NIX_DROPIN_DIR"
              cat > "$NIX_DROPIN_DIR/proxy.conf" << EOF
              [Service]
              EnvironmentFile=$PROXY_ENV
              EOF
              echo "  ✓ nix-daemon proxy drop-in created"

              # Configure Docker daemon proxy
              DOCKER_DROPIN_DIR="/run/systemd/system/docker.service.d"
              mkdir -p "$DOCKER_DROPIN_DIR"
              cat > "$DOCKER_DROPIN_DIR/proxy.conf" << EOF
              [Service]
              EnvironmentFile=$PROXY_ENV
              EOF
              echo "  ✓ docker proxy drop-in created"

              # Reload systemd to pick up the drop-ins
              systemctl daemon-reload
              echo "  ✓ systemd daemon reloaded"

              # Restart services to apply proxy settings (ONLY if already active)
              # Before= ordering means services are blocked from starting until we complete.
              # On clean boot: services not active → no restart needed → drop-ins apply on first start
              # On socket activation race: service became active early → restart applies config
              # CRITICAL: Never restart services in "waiting" state (job queue) - causes deadlock
              echo "Checking services for proxy configuration apply..."

              # Only restart nix-daemon if it's currently active (not waiting in job queue)
              if systemctl is-active --quiet nix-daemon.service 2>/dev/null; then
                systemctl restart nix-daemon.service && echo "  ✓ nix-daemon restarted (was active)"
              else
                echo "  · nix-daemon not yet active (will use proxy config on first start)"
              fi

              # Only restart docker if it's currently active (not waiting in job queue)
              if systemctl is-active --quiet docker.service 2>/dev/null; then
                systemctl restart docker.service && echo "  ✓ docker restarted (was active)"
              else
                echo "  · docker not yet active (will use proxy config on first start)"
              fi

              echo "Proxy configuration applied to system services"
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
          # Wait for cloud-init to write files (cluster-ca.crt)
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
            "konductor.service"
          ];
          wants = [
            "network-online.target"
            "docker.service"
          ];
          requires = [
            "konductor-ca-setup.service"
            "konductor.service"
          ];
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

        # =====================================================================
        # Multi-User Service Orchestration
        # =====================================================================
        # Template units for per-user services with deterministic port allocation.
        # Orchestrator reads /var/lib/konductor/services.toml and instantiates
        # services dynamically by generating drop-ins to /run/systemd/system/.
        #
        # Port Convention: base_port + (uid - 1000)
        # - Ensures no collisions between users
        # - Deterministic and discoverable
        # - One instance per user per service
        # - Keeps ports within reasonable range
        #
        # Example: ttyd base 7000 + (alice UID 1004 - 1000) = port 7004
        # =====================================================================
      }
      # Merge in service templates generated by mkKonductorService
      // (mkKonductorService {
        # Template: TTYd Web Terminal (per-user instances)
        # Base port: 7000, actual port = 7000 + (UID - 1000)
        serviceName = "ttyd";
        basePort = 7000;
        afterServices = [ "network.target" "konductor-init.service" "konductor-pki.service" ];
        documentation = [ "https://github.com/tsl0922/ttyd" ];
        workingDirectory = "/home/%i";
      })
      // (mkKonductorService {
        # Template: VSCode Server (per-user instances)
        # Base port: 8000, actual port = 8000 + (UID - 1000)
        # REQUIRES drop-in from konductor-init.service with actual configuration
        serviceName = "vscode";
        basePort = 8000;
        documentation = [ "https://github.com/coder/code-server" ];
        extraServiceConfig = {
          Restart = "no";  # Don't restart on failure - requires intervention
        };
      })
      // (mkKonductorService {
        # Template: Restty Web Terminal (per-user instances)
        # Base port: 9000, actual port = 9000 + (UID - 1000)
        serviceName = "restty";
        basePort = 9000;
        documentation = [ "https://github.com/wiedymi/restty" ];
        extraServiceConfig = {
          MemoryDenyWriteExecute = false; # Required for WASM
        };
      })
      // (mkKonductorService {
        # Template: Ghostty Web Terminal (per-user instances)
        # Base port: 10000, actual port = 10000 + (UID - 1000)
        serviceName = "ghostty";
        basePort = 10000;
        documentation = [ "https://github.com/coder/ghostty-web" ];
      })
      // {

        # =====================================================================
        # Konductor Service Orchestrator (konductor-init.service)
        # =====================================================================
        # Reads /var/lib/konductor/services.toml and orchestrates service lifecycle:
        # 1. Parse configuration file
        # 2. Generate drop-ins to /run/systemd/system/ with port assignments
        # 3. Call systemctl daemon-reload
        # 4. Start/stop services based on enabled state
        #
        # Reloadable: systemctl reload konductor-init.service applies config changes
        # =====================================================================
        konductor-init =
          let
            orchestratorScript = pkgs.writeShellScript "konductor-init-start" ''
              set -euo pipefail

              CONFIG_FILE="/var/lib/konductor/services.toml"
              DROPIN_BASE="/run/systemd/system"
              ENV_DIR="/var/lib/konductor/env"
              STATE_DIR="/var/lib/konductor/state"

              mkdir -p "$ENV_DIR" "$STATE_DIR" "$DROPIN_BASE"

              echo "═══════════════════════════════════════════════════════════════════════════════"
              echo "                    Konductor Service Orchestrator"
              echo "═══════════════════════════════════════════════════════════════════════════════"

              if [ ! -f "$CONFIG_FILE" ]; then
                echo "⚠  Configuration not found: $CONFIG_FILE"
                echo "   Skipping service orchestration (deploy-time config not provided)"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                exit 0
              fi

              echo "✓  Configuration found: $CONFIG_FILE"

              # Parse TOML to JSON using yj with validation
              if ! CONFIG_JSON=$(yj -t < "$CONFIG_FILE" 2>&1); then
                echo "✗  Failed to parse TOML configuration:"
                echo "   $CONFIG_JSON"
                echo "   Syntax error in $CONFIG_FILE"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                exit 1
              fi

              if [ -z "$CONFIG_JSON" ]; then
                echo "✗  Parsed configuration is empty"
                echo "═══════════════════════════════════════════════════════════════════════════════"
                exit 1
              fi

              # Initialize state files on first boot
              touch "$STATE_DIR/enabled.list"

              # Clear new enabled list
              > "$STATE_DIR/enabled.list.new"

              # ─────────────────────────────────────────────────────────────────────
              # Process Per-User Services (ALL users via templates)
              # ─────────────────────────────────────────────────────────────────────
              echo ""
              echo "┌─ Per-User Services ───────────────────────────────────────────────────────────┐"

              # Extract port_bases for calculations
              PORT_BASES=$(echo "$CONFIG_JSON" | jq -r '.port_bases // {}')

              # Extract user_services section
              USER_SERVICES=$(echo "$CONFIG_JSON" | jq -r '
                .user_services // {} |
                to_entries[] |
                .key as $user |
                .value |
                to_entries[] |
                select(.value == true) |
                "\($user)|\(.key)"
              ')

              if [ -z "$USER_SERVICES" ]; then
                echo "  No per-user services enabled"
              else
                while IFS='|' read -r username svc_name; do
                  # Verify user exists
                  if ! USER_UID=$(id -u "$username" 2>/dev/null); then
                    echo "  ⚠  User $username not found, skipping $svc_name"
                    continue
                  fi

                  # Validate UID range (must be >= 1000 for port formula)
                  if [ "$USER_UID" -lt 1000 ]; then
                    echo "  ✗  User $username UID $USER_UID < 1000 (invalid for port formula)"
                    continue
                  fi

                  # Get base port for this service
                  BASE_PORT=$(echo "$PORT_BASES" | jq -r --arg svc "$svc_name" '.[$svc] // 0')
                  if [ "$BASE_PORT" -eq 0 ]; then
                    echo "  ⚠  No base port defined for $svc_name, skipping"
                    continue
                  fi

                  # Calculate port: base_port + (uid - 1000)
                  CALC_PORT=$((BASE_PORT + USER_UID - 1000))

                  # Validate calculated port is in valid range
                  if [ "$CALC_PORT" -lt 1024 ] || [ "$CALC_PORT" -gt 65535 ]; then
                    echo "  ✗  Calculated port $CALC_PORT out of range (1024-65535) for $svc_name@$username"
                    continue
                  fi

                  echo "  Configuring: $svc_name@$username"
                  echo "    User UID: $USER_UID"
                  echo "    Base Port: $BASE_PORT"
                  echo "    Calculated Port: $CALC_PORT"

                  # Generate environment file
                  ENV_FILE="$ENV_DIR/konductor-''${svc_name}@''${username}.env"
                  cat > "$ENV_FILE" << EOF
              PORT=$CALC_PORT
              USER_UID=$USER_UID
              WORKSPACE=/workspace
EOF

                  # Generate drop-in
                  SERVICE_NAME="konductor-''${svc_name}@''${username}.service"
                  DROPIN_PATH="$DROPIN_BASE/''${SERVICE_NAME}.d"
                  mkdir -p "$DROPIN_PATH"

                  cat > "$DROPIN_PATH/50-config.conf" << EOF
              [Service]
              EnvironmentFile=$ENV_FILE

              # Override ExecStart with calculated port
              ExecStart=
EOF

                  # Service-specific ExecStart overrides
                  # All services use multi-tier certificate precedence (cluster→hypervisor→self-signed)
                  # Certificate variables (CERT_PATH, KEY_PATH) come from ExecStartPre cert detection
                  case "$svc_name" in
                    ttyd)
                      cat >> "$DROPIN_PATH/50-config.conf" << EOF
ExecStart=${pkgs.ttyd}/bin/ttyd \\
  --port \''${PORT} \\
  --ssl \\
  --ssl-cert \''${CERT_PATH} \\
  --ssl-key \''${KEY_PATH} \\
  bash
EOF
                      ;;
                    restty)
                      cat >> "$DROPIN_PATH/50-config.conf" << EOF
ExecStart=${(import ../programs/restty-web { inherit pkgs lib; }).server}/bin/restty-web-server \\
  --port \''${PORT} \\
  --cert \''${CERT_PATH} \\
  --key \''${KEY_PATH} \\
  --writable \\
  --working-directory /workspace
EOF
                      ;;
                    ghostty)
                      cat >> "$DROPIN_PATH/50-config.conf" << EOF
ExecStart=${(import ../programs/ghostty-web { inherit pkgs lib; }).server}/bin/ghostty-web-server \\
  --port \''${PORT} \\
  --cert \''${CERT_PATH} \\
  --key \''${KEY_PATH} \\
  --writable \\
  --working-directory /workspace
EOF
                      ;;
                    vscode)
                      cat >> "$DROPIN_PATH/50-config.conf" << EOF
ExecStartPre=/bin/sh -c 'mkdir -p /home/''${username}/.local/share/code-server/extensions && for ext in ${vscodeExtensionsDir}/share/vscode/extensions/*; do ln -sfn "\$ext" /home/''${username}/.local/share/code-server/extensions/; done'
ExecStartPre=/bin/sh -c 'mkdir -p /home/''${username}/.local/share/code-server/User && test -f /home/''${username}/.local/share/code-server/User/settings.json || cp ${vscodeDefaultSettings} /home/''${username}/.local/share/code-server/User/settings.json'
ExecStart=${pkgs.code-server}/bin/code-server \\
  --bind-addr 0.0.0.0:\''${PORT} \\
  --user-data-dir /home/''${username}/.local/share/code-server \\
  --extensions-dir /home/''${username}/.local/share/code-server/extensions \\
  --auth none \\
  --cert \''${CERT_PATH} \\
  --cert-key \''${KEY_PATH} \\
  --disable-telemetry \\
  --disable-update-check \\
  --disable-getting-started-override \\
  /workspace
EOF
                      ;;
                    *)
                      echo "  ✗  Unknown service: $svc_name"
                      continue
                      ;;
                  esac

                  echo "    ✓ Env file: $ENV_FILE"
                  echo "    ✓ Drop-in: $DROPIN_PATH/50-config.conf"

                  # Track enabled service
                  echo "$SERVICE_NAME" >> "$STATE_DIR/enabled.list.new"

                done <<< "$USER_SERVICES"
              fi

              echo "└───────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # Reload systemd and manage services
              # ─────────────────────────────────────────────────────────────────────
              echo ""
              echo "Reloading systemd daemon..."
              systemctl daemon-reload
              echo "✓  systemd daemon-reload complete"

              echo ""
              echo "┌─ Service Lifecycle Management ────────────────────────────────────────────────┐"

              # Start newly enabled services
              if [ -f "$STATE_DIR/enabled.list.new" ]; then
                sort -u "$STATE_DIR/enabled.list.new" | while read SERVICE; do
                  if ! systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
                    echo "  ↑ Starting: $SERVICE"
                    systemctl start "$SERVICE" && echo "    ✓ Started" || echo "    ✗ Failed to start"
                  else
                    echo "  ✓ Already active: $SERVICE"
                  fi
                done
              fi

              # Stop services that were removed from config
              if [ -f "$STATE_DIR/enabled.list" ]; then
                comm -23 <(sort "$STATE_DIR/enabled.list") <(sort "$STATE_DIR/enabled.list.new" 2>/dev/null || true) | while read SERVICE; do
                  if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
                    echo "  ↓ Stopping: $SERVICE (removed from config)"
                    systemctl stop "$SERVICE" && echo "    ✓ Stopped" || echo "    ✗ Failed to stop"
                  fi
                done
              fi

              # Update state
              [ -f "$STATE_DIR/enabled.list.new" ] && mv "$STATE_DIR/enabled.list.new" "$STATE_DIR/enabled.list"

              echo "└───────────────────────────────────────────────────────────────────────────────┘"

              echo ""
              echo "═══════════════════════════════════════════════════════════════════════════════"
              echo "  ✓ Orchestration Complete"
              echo "  View services: systemctl list-units 'konductor-*'"
              echo "  Edit config: vi /var/lib/konductor/services.toml"
              echo "  Reload: systemctl reload konductor-init.service"
              echo "═══════════════════════════════════════════════════════════════════════════════"
            '';
          in
          {
            description = "Konductor Service Orchestrator";
            documentation = [ "https://github.com/containercraft/konductor" ];

            # Wait for all boot dependencies
            after = [
              "cloud-init.service"
              "network-online.target"
              "konductor-proxy-setup.service"
              "workspace-mount.service"
            ];
            wants = [ "network-online.target" ];

            wantedBy = [ "multi-user.target" ];

            path = with pkgs; [
              coreutils
              gnused
              gnugrep
              gawk
              systemd
              util-linux
              yj  # TOML to JSON converter
              yq-go  # YAML/TOML/JSON processor
              jq  # JSON query processor
              findutils
            ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "konductor-init";

              # Orchestrator script handles both start and reload (idempotent)
              ExecStart = orchestratorScript;
              ExecReload = orchestratorScript;
            };
          };

        # =====================================================================
        # Configuration Reload Service (triggered by path watcher)
        # =====================================================================
        # Triggered by konductor-config-watcher.path when services.toml changes.
        # Reloads konductor-init.service which reconciles service state.
        # =====================================================================
        konductor-config-reload = {
          description = "Reload Konductor services from configuration file";
          documentation = [ "https://github.com/containercraft/konductor" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "konductor-config-reload" ''
              echo "Configuration change detected, reloading konductor-init.service..."
              if systemctl is-active --quiet konductor-init.service; then
                systemctl reload konductor-init.service
              else
                systemctl start konductor-init.service
              fi
            '';
          };
        };

        # =====================================================================
        # Nix Store Overlay Service
        # =====================================================================
        # Systemd service to set up nix store overlay when host store is available
        # This runs early in boot, before nix-daemon, and only activates during
        # QCOW2 build when the host's /nix/store is mounted via 9p virtfs.
        # Note: No ConditionPathIsMountPoint since we use automount - the script
        # checks availability by accessing the path (triggering automount if device exists)
        nix-store-overlay = {
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

              # =====================================================================
              # Check for 9p device BEFORE triggering automount
              # =====================================================================
              # The /nix/.host-store mount is configured with x-systemd.automount,
              # which triggers on directory access. Checking the directory existence
              # would trigger the automount and cause kernel errors if no 9p device.
              #
              # Instead, check for virtio 9p devices by scanning mount_tag files.
              # Each virtio 9p device exposes its tag in /sys/bus/virtio/devices/*/mount_tag
              #
              # Wait up to 10 seconds for virtio devices to enumerate (boot timing)
              FOUND_NIXSTORE=0
              for i in $(${pkgs.coreutils}/bin/seq 1 10); do
                VIRTIO_9P_DEVICES=$(${pkgs.findutils}/bin/find /sys/bus/virtio/devices -name 'mount_tag' -exec ${pkgs.coreutils}/bin/cat {} \; 2>/dev/null || true)
                if echo "$VIRTIO_9P_DEVICES" | ${pkgs.gnugrep}/bin/grep -q "nixstore"; then
                  FOUND_NIXSTORE=1
                  echo "Found 9p device 'nixstore' after ''${i}s"
                  break
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done

              if [ "$FOUND_NIXSTORE" -eq 0 ]; then
                echo "9p device 'nixstore' not available (production mode), using local store"
                exit 0
              fi

              # Device exists, now safe to check host store content (will trigger automount)
              if [ ! -d /nix/.host-store ] || [ -z "$(${pkgs.coreutils}/bin/ls -A /nix/.host-store 2>/dev/null)" ]; then
                echo "Host store mounted but empty, using local store"
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
      };
    };

    # =====================================================================
    # Configuration File Watcher (systemd.path)
    # =====================================================================
    # Watches /var/lib/konductor/services.toml for changes and triggers reload.
    # Enables workflow:
    # 1. Manual: Edit services.toml → auto-reload
    # 2. Portal: ConfigMap → NFS mount → file change → auto-reload
    # =====================================================================
    systemd.paths = {
      konductor-config-watcher = {
        description = "Watch Konductor configuration for changes";
        documentation = [ "https://github.com/containercraft/konductor" ];

        wantedBy = [ "multi-user.target" ];

        pathConfig = {
          PathModified = "/var/lib/konductor/services.toml";
          Unit = "konductor-config-reload.service";
        };
      };
    };

    # Services configuration
    services = {
      # SSH for VM access (key-only, no password fallback)
      openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
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

      # =========================================================================
      # Cloud-init Configuration
      # =========================================================================
      # CRITICAL: NixOS cloud-init module uses lib.mkDefault, causing settings
      # to MERGE with defaults instead of replacing them. We use lib.mkForce
      # on module lists to ensure removed modules (migrator, rightscale_userdata)
      # are actually excluded.
      #
      # Serial console (ttyS0) is our trusted compute logging pathway.
      # All cloud-init output goes to serial for KubeVirt pod log collection.
      #
      # See: docs/developer_guide/qcow2/CLOUD_INIT_NIXOS_INTEGRATION.md
      # See: nixos/modules/services/system/cloud-init.nix for NixOS defaults
      cloud-init = {
        enable = true;
        network.enable = true;  # Enables systemd-networkd integration

        settings = {
          # ─────────────────────────────────────────────────────────────────────
          # System Information
          # ─────────────────────────────────────────────────────────────────────
          system_info = {
            distro = "nixos";
            paths = {
              cloud_dir = "/var/lib/cloud";
              run_dir = "/run/cloud-init";
            };
            # Force systemd-networkd only - skip netplan/OVS/NetworkManager checks
            network = {
              renderers = [ "networkd" ];
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Datasource Configuration - NoCloud for KubeVirt/QEMU
          # ─────────────────────────────────────────────────────────────────────
          datasource_list = [ "NoCloud" "ConfigDrive" "None" ];

          # ─────────────────────────────────────────────────────────────────────
          # Users - Use list syntax (string syntax deprecated in 22.2)
          # ─────────────────────────────────────────────────────────────────────
          # Empty list prevents automatic default user creation at UID 1000
          # Allows cloud-init userdata to create explicit users dynamically
          # Preserves UID 1000 for runtime user creation from userdata
          users = [ ];
          disable_root = false;
          preserve_hostname = false;

          # ─────────────────────────────────────────────────────────────────────
          # Output Configuration - Serial Console as Trusted Pathway
          # ─────────────────────────────────────────────────────────────────────
          # Redirect ALL cloud-init command output to serial console.
          # This is captured by KubeVirt pod log collector and shipped to
          # upstream log analysis. Serial console is our single pane of glass.
          output = {
            all = "| tee -a /dev/ttyS0";
          };

          # ─────────────────────────────────────────────────────────────────────
          # Logging Configuration - Python logging to serial + journald
          # ─────────────────────────────────────────────────────────────────────
          # This configures Python's logging module for cloud-init internal logs.
          # The output section (above) handles shell command stdout/stderr.
          # Together they ensure ALL cloud-init output goes to serial console.
          log_cfgs = [
            [
              ''
              [loggers]
              keys=root,cloudinit

              [handlers]
              keys=consoleHandler,serialHandler

              [formatters]
              keys=simpleFormatter

              [logger_root]
              level=DEBUG
              handlers=consoleHandler

              [logger_cloudinit]
              level=DEBUG
              handlers=consoleHandler,serialHandler
              qualname=cloudinit
              propagate=0

              [handler_consoleHandler]
              class=StreamHandler
              level=DEBUG
              formatter=simpleFormatter
              args=(sys.stderr,)

              [handler_serialHandler]
              class=FileHandler
              level=DEBUG
              formatter=simpleFormatter
              args=('/dev/ttyS0', 'a')

              [formatter_simpleFormatter]
              format=%(asctime)s - %(filename)s[%(levelname)s]: %(message)s
              datefmt=%Y-%m-%dT%H:%M:%S
              ''
            ]
          ];

          # ─────────────────────────────────────────────────────────────────────
          # Init Stage Modules (cloud-init init)
          # ─────────────────────────────────────────────────────────────────────
          # CRITICAL: lib.mkForce REPLACES NixOS defaults (which include "migrator")
          # Without mkForce, our list MERGES with defaults and removed modules appear.
          #
          # EXCLUDED:
          #   - migrator: REMOVED in cloud-init 24.1
          #   - rsyslog: NixOS uses journald
          #   - resolv_conf: systemd-resolved on NixOS
          cloud_init_modules = lib.mkForce [
            "seed_random"
            "bootcmd"
            "write_files"
            "growpart"
            "resizefs"
            "disk_setup"
            "mounts"
            "set_hostname"
            "update_hostname"
            "update_etc_hosts"
            "ca_certs"
            "users_groups"
            "ssh"
          ];

          # ─────────────────────────────────────────────────────────────────────
          # Config Stage Modules (cloud-init modules --mode=config)
          # ─────────────────────────────────────────────────────────────────────
          # EXCLUDED:
          #   - locale: Raises NotImplementedError on NixOS
          #   - timezone: Silent no-op on NixOS (use time.timeZone instead)
          #   - ntp: NixOS handles NTP declaratively
          #   - ssh_import_id: Not verified on NixOS
          #   - apt_*, grub_dpkg, yum_*, zypper_*: Distro-specific
          cloud_config_modules = lib.mkForce [
            "disk_setup"
            "mounts"
            "set_passwords"
            "runcmd"
            "ssh"
          ];

          # ─────────────────────────────────────────────────────────────────────
          # Final Stage Modules (cloud-init modules --mode=final)
          # ─────────────────────────────────────────────────────────────────────
          # EXCLUDED:
          #   - rightscale_userdata: REMOVED in cloud-init 24.1
          #   - keys_to_console: Helper path broken on NixOS FHS
          #   - package_update_upgrade_install: Raises NotImplementedError on NixOS
          cloud_final_modules = lib.mkForce [
            "scripts_vendor"
            "scripts_per_once"
            "scripts_per_boot"
            "scripts_per_instance"
            "scripts_user"
            "ssh_authkey_fingerprints"
            "phone_home"
            "final_message"
            "power_state_change"
          ];
        };
      };

      # Spice/QEMU guest tools for clipboard, display, etc.
      spice-vdagentd.enable = true;
    };

    # =====================================================================
    # Virtualisation Configuration
    # =====================================================================
    virtualisation = {
      # Disk size for VM - increased to accommodate full package set
      diskSize = lib.mkDefault (30 * 1024); # 30GB (full konductor environment)

      # Docker - starts on boot after cloud-init and proxy configuration
      # Ordering: cloud-init → konductor-proxy-setup → docker
      docker = {
        enable = true;
        enableOnBoot = true;

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
      # NOTE: Linux uses LAST console= as primary. tty0 must be last for kbd_mode
      # to work (serial consoles don't support keyboard ioctls).
      kernelParams = [
        "console=ttyS0,115200"  # Serial console (receives all kernel messages)
        "console=tty0"          # VGA console (primary - receives kbd_mode)
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
      initrd = {
        # Enable systemd in initrd for /etc overlay support
        # Required for system.etc.overlay.enable to work reliably
        # See: nixos/tests/activation/etc-overlay-mutable.nix
        systemd.enable = true;

        availableKernelModules = [
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
        # NOTE: /etc/mtab symlink is handled automatically by systemd initrd
        # (previously used postDeviceCommands which is incompatible with systemd initrd)
      };
    };

    # =====================================================================
    # PKI Trust Configuration (Git CA Trust)
    # =====================================================================
    # Configure global git settings for all users
    # Points directly to mounted hypervisor CA (available at runtime)
    # If CA not mounted, git will fall back to system CA bundle
    environment.etc."gitconfig".text = ''
      [http]
        sslCAInfo = /mnt/pki/ca.crt
      [safe]
        directory = /workspace
    '';

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
