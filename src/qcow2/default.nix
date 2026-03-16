# src/qcow2/default.nix
# QCOW2 VM image builder using native nixpkgs (no nixos-generators)
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
# Uses custom make-disk-image-fast.nix that copies files INSIDE the VM
# via virtiofs instead of slow cptofs (LKL). 5-10x faster for large closures.
#
# Services installed but not auto-started (lean boot).
# Start via cloud-init or: systemctl start docker libvirtd

{ pkgs
, lib
, nixpkgs
, # For lib.nixosSystem
  inputs
, system
, versions
, programs
, devshells
, # CI devshell closure baked into image
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
  # Named 'konductorConfig' to avoid shadowing NixOS 'config' in modules
  konductorConfig = import ../config { inherit pkgs lib versions catppuccinSources; };

  # Import packages with wrapped config (hermetic linters/formatters)
  devshellPackages = import ../packages {
    inherit
      pkgs
      lib
      versions
      ;
    config = konductorConfig;
  };

  # Konductor self-hosting packages (docker, qemu, libvirt, etc.)
  inherit (devshellPackages) konductor;

  # Open Sesame headless package (profile, secrets, launcher, snippets daemons)
  openSesamePkg = inputs.open-sesame.packages.${system}.open-sesame-headless;

  # Systemd mount service template for virtio disk mounting
  mountService = import ./konductor-mount-template.nix { inherit pkgs; };

  # Pre-installed VS Code extensions for code-server
  # Symlinked into each user's extensions dir at service start
  vscodeExtensionsList = with pkgs.vscode-extensions; [
    # Theme
    catppuccin.catppuccin-vsc # Catppuccin theme (default)
    catppuccin.catppuccin-vsc-icons # Catppuccin file icons

    # Language support — Python
    ms-python.python # Python language server + debugging
    ms-python.vscode-pylance # Pylance type checker
    ms-python.debugpy # Python debugger
    charliermarsh.ruff # Ruff linter/formatter

    # Language support — Go
    golang.go # Go language server (gopls)

    # Language support — Rust
    rust-lang.rust-analyzer # Rust analyzer

    # Language support — JavaScript/TypeScript
    dbaeumer.vscode-eslint # ESLint integration

    # Language support — Nix
    jnoortheen.nix-ide # Nix language support
    mkhl.direnv # direnv integration

    # Language support — Shell
    timonwong.shellcheck # ShellCheck linter
    foxundermoon.shell-format # Shell script formatter

    # Config file support
    redhat.vscode-yaml # YAML language server
    tamasfe.even-better-toml # TOML language server
    ms-azuretools.vscode-docker # Dockerfile + Compose

    # Editor tools
    editorconfig.editorconfig # EditorConfig support
    esbenp.prettier-vscode # Prettier formatter
    christian-kohler.path-intellisense # Path autocompletion
    gruntfuggly.todo-tree # TODO/FIXME tree view
    usernamehw.errorlens # Inline error/warning display
    vscodevim.vim # Vim keybindings
    streetsidesoftware.code-spell-checker # Spell checking
    alefragnani.bookmarks # Bookmarkable lines
    formulahendry.auto-rename-tag # Auto-rename paired HTML/XML tags

    # Markdown
    bierner.github-markdown-preview # GitHub-flavored markdown preview
    bierner.markdown-mermaid # Mermaid diagram support
    davidanson.vscode-markdownlint # Markdown linting
    yzhang.markdown-all-in-one # Markdown TOC, preview, shortcuts

    # Remote development
    ms-vscode-remote.remote-ssh # SSH into remote hosts
    ms-vscode-remote.remote-ssh-edit # Edit SSH config
    ms-vscode-remote.remote-containers # Dev containers support
    ms-vscode.remote-explorer # Remote explorer UI

    # Infrastructure
    ms-kubernetes-tools.vscode-kubernetes-tools # Kubernetes cluster management

    # Nix (additional)
    bbenoist.nix # Nix syntax highlighting
    arrterian.nix-env-selector # Nix environment selector

    # Debugging
    vadimcn.vscode-lldb # LLDB debugger (Rust/C/C++)

    # Collaboration
    ms-vsliveshare.vsliveshare # Live Share real-time collaboration

    # Git & GitHub
    eamodio.gitlens # Git blame, history, annotations
    mhutchie.git-graph # Git commit graph visualization
    github.vscode-github-actions # GitHub Actions workflow support
    github.vscode-pull-request-github # GitHub PR and issue integration

    # AI
    github.copilot # GitHub Copilot
    github.copilot-chat # GitHub Copilot Chat
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
      bash = { path = "/bin/bash"; args = [ "-l" ]; };
    };

    # Editor
    "editor.fontFamily" = "JetBrainsMono Nerd Font, monospace";
    "editor.fontSize" = 14;
    "editor.lineNumbers" = "relative";
    "editor.formatOnSave" = true;
    "editor.formatOnPaste" = true;
    "editor.rulers" = [ 80 120 ];
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

  # =====================================================================
  # VS Code Remote SSH Support (buildFHSEnv + node patching)
  # =====================================================================
  # VS Code Remote SSH downloads pre-compiled node binaries that expect
  # FHS paths (/lib64/ld-linux-x86-64.so.2, /lib/libstdc++.so.6, etc).
  # On NixOS, these paths don't exist. The nixos-vscode-server approach:
  # 1. Create an FHS environment with nodejs and required libraries
  # 2. Replace VS Code's node binary with a symlink to this FHS wrapper
  # 3. Watch for new VS Code server installations and patch them
  #
  # This integrates with konductor's orchestrator (konductor-init.service)
  # to automatically start the watcher for users with vscode enabled.

  # FHS environment wrapping nodejs - provides all libraries VS Code needs
  vscodeServerFHS = pkgs.buildFHSEnv {
    name = "vscode-server-fhs";
    targetPkgs = pkgs: with pkgs; [
      # Core runtime
      nodejs_20
      stdenv.cc.libc # glibc (libc.so, ld-linux)
      stdenv.cc.cc.lib # libstdc++, libgcc_s

      # Libraries VS Code and extensions commonly need
      zlib # Compression
      openssl # SSL/TLS
      icu # Unicode/i18n
      curl # HTTP client
      libsecret # Secret storage
      xorg.libX11 # X11 (for clipboard, etc.)
      xorg.libxcb # XCB
    ];
    runScript = "${pkgs.nodejs_20}/bin/node";
  };

  # Script to patch VS Code server node binary by symlinking to FHS wrapper
  # Called by konductor-vscode-fix@.service on startup and when new installs detected
  vscodeServerPatchScript = pkgs.writeShellScript "vscode-server-patch" ''
    set -euo pipefail
    USER_HOME="$1"

    patch_node() {
      local node_path="$1"
      # Only patch if it's a real binary (not already a symlink to our FHS)
      if [ -f "$node_path" ] && [ ! -L "$node_path" ]; then
        echo "[vscode-fix] Patching: $node_path"
        # Backup original binary (for debugging if needed)
        mv "$node_path" "$node_path.orig" 2>/dev/null || true
        # Symlink to FHS-wrapped nodejs
        ln -sf ${vscodeServerFHS}/bin/vscode-server-fhs "$node_path"
        echo "[vscode-fix] ✓ Patched successfully"
        return 0
      elif [ -L "$node_path" ]; then
        # Already a symlink - check if it points to our FHS
        local target
        target=$(readlink -f "$node_path" 2>/dev/null || echo "")
        if [[ "$target" == *"vscode-server-fhs"* ]]; then
          echo "[vscode-fix] Already patched: $node_path"
          return 0
        fi
      fi
      return 1
    }

    PATCHED=0

    # VS Code stable/insiders paths
    for vscode_dir in ".vscode-server" ".vscode-server-insiders"; do
      BASE_DIR="$USER_HOME/$vscode_dir"

      # Standard VS Code Remote SSH paths
      if [ -d "$BASE_DIR/bin" ]; then
        for dir in "$BASE_DIR/bin"/*; do
          [ -d "$dir" ] && [ -f "$dir/node" ] && patch_node "$dir/node" && PATCHED=$((PATCHED + 1))
        done
      fi

      # CLI servers path (newer VS Code versions)
      if [ -d "$BASE_DIR/cli/servers" ]; then
        for dir in "$BASE_DIR/cli/servers"/*/*; do
          [ -d "$dir" ] && [ -f "$dir/node" ] && patch_node "$dir/node" && PATCHED=$((PATCHED + 1))
        done
      fi
    done

    # VSCodium paths
    for vscode_dir in ".vscodium-server"; do
      BASE_DIR="$USER_HOME/$vscode_dir"

      if [ -d "$BASE_DIR/bin" ]; then
        for dir in "$BASE_DIR/bin"/*; do
          [ -d "$dir" ] && [ -f "$dir/node" ] && patch_node "$dir/node" && PATCHED=$((PATCHED + 1))
        done
      fi
    done

    if [ "$PATCHED" -gt 0 ]; then
      echo "[vscode-fix] Patched $PATCHED node binary/binaries"
    else
      echo "[vscode-fix] No unpatched node binaries found"
    fi
  '';

  # Dummy ldconfig wrapper for VS Code Remote SSH pre-flight checks
  # VS Code CLI runs `ldconfig -p | grep libstdc++` to verify glibc environment.
  # NixOS ldconfig errors (no /etc/ld.so.cache), causing pre-flight to fail.
  # This wrapper satisfies the check by returning expected output.
  # Added to environment.systemPackages to be in PATH before real ldconfig.
  vscodeLdconfigWrapper = pkgs.writeShellScriptBin "ldconfig" ''
    # Dummy ldconfig for NixOS - satisfies VS Code Remote SSH pre-flight checks
    # Real libraries provided by nix-ld at runtime
    if [ "$1" = "-p" ]; then
      echo "	libstdc++.so.6 (libc6,x86-64) => /lib/libstdc++.so.6"
      echo "	libgcc_s.so.1 (libc6,x86-64) => /lib/libgcc_s.so.1"
      exit 0
    fi
    exit 0
  '';

  # Watcher script that monitors for new VS Code server installations
  vscodeServerWatchScript = pkgs.writeShellScript "vscode-server-watch" ''
    set -euo pipefail
    USERNAME="$1"
    USER_HOME="/home/$USERNAME"

    # Directories to watch for new VS Code server installations
    WATCH_DIRS=(
      "$USER_HOME/.vscode-server/bin"
      "$USER_HOME/.vscode-server/cli/servers"
      "$USER_HOME/.vscode-server-insiders/bin"
      "$USER_HOME/.vscode-server-insiders/cli/servers"
      "$USER_HOME/.vscodium-server/bin"
    )

    # Create watch directories if they don't exist
    for dir in "''${WATCH_DIRS[@]}"; do
      mkdir -p "$dir" 2>/dev/null || true
    done

    echo "[vscode-fix] Watching for new VS Code server installations..."
    echo "[vscode-fix] Directories: ''${WATCH_DIRS[*]}"

    # Filter to only existing directories for inotifywait
    EXISTING_DIRS=()
    for dir in "''${WATCH_DIRS[@]}"; do
      [ -d "$dir" ] && EXISTING_DIRS+=("$dir")
    done

    if [ ''${#EXISTING_DIRS[@]} -eq 0 ]; then
      echo "[vscode-fix] No watch directories exist yet, waiting for creation..."
      # Wait for any of the base directories to be created
      ${pkgs.inotify-tools}/bin/inotifywait -m -e create "$USER_HOME" 2>/dev/null | while read -r _ event filename; do
        case "$filename" in
          .vscode-server|.vscode-server-insiders|.vscodium-server)
            echo "[vscode-fix] VS Code directory created: $filename"
            # Re-exec to pick up new directories
            exec "$0" "$USERNAME"
            ;;
        esac
      done
    fi

    # Watch for new VS Code server installations
    ${pkgs.inotify-tools}/bin/inotifywait -m -e create,isdir "''${EXISTING_DIRS[@]}" 2>/dev/null | while read -r directory event filename; do
      if [[ "$event" == *"CREATE"* ]] && [[ "$event" == *"ISDIR"* ]]; then
        echo "[vscode-fix] New VS Code server detected: $directory$filename"
        # Wait a moment for download to complete
        sleep 3
        # Run patch script
        ${vscodeServerPatchScript} "$USER_HOME"
      fi
    done
  '';

  # Common home-manager configuration for built-in users
  # Provisions shell configs (.bashrc, .bash_profile, etc.) at build time
  # Uses canonical config from src/config/shell/ (SSOT)
  homeManagerUserConfig = {
    imports = [ inputs.open-sesame.homeManagerModules.default ];

    programs.open-sesame = {
      enable = true;
      headless = true;
    };

    home = {
      inherit (versions.nixos) stateVersion;
      file = {
        ".bashrc".text = konductorConfig.shell.bash.bashrcContent;
        ".bash_profile".text = shellContent.bashProfileContent;
        ".inputrc".text = shellContent.inputrcContent;
        ".config/starship.toml".text = konductorConfig.shell.starship.configContent;
        ".config/atuin/config.toml" = {
          text = konductorConfig.shell.atuin.configContent;
          force = true; # Overwrite existing atuin config
        };
        ".envrc".text = ''
          # Konductor VM - all packages pre-installed system-wide
          # This .envrc is for project-specific env vars only
          dotenv_if_exists .env
          dotenv_if_exists "$HOME/.env"
        '';
      };
    };
  };

  # Service template generator for konductor multi-user services
  # Reduces code duplication by abstracting common patterns:
  # - Dynamic firewall management (ExecStartPre opens port, ExecStopPost closes)
  # - Certificate precedence detection (Tier 1→2→3 fallback)
  # - RuntimeDirectory for /run/konductor state
  # - EnvironmentFile pattern for PORT and cert variables
  mkKonductorService =
    { serviceName
    , # Service name (ttyd, vscode, restty, ghostty)
      # NOTE: Do NOT include konductor-init.service here - creates circular dependency!
      # konductor-init starts these services, so they can't wait for init to complete.
      # The drop-in config is written BEFORE init calls systemctl start.
      # Wait for both cert generation AND permissions. konductor-pki-permissions alone
      # is not a reliable gate — its ConditionPathExists skips silently if certs don't
      # exist yet, satisfying After= without certs actually being ready.
      afterServices ? [ "network.target" "konductor-pki-vm.service" "konductor-pki-permissions.service" ]
    , documentation ? [ ]
    , workingDirectory ? "/workspace"
    , extraServiceConfig ? { }
    , # Additional serviceConfig options
      ...
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
            # NOTE: %i is passed as $1 because systemd specifiers aren't expanded inside scripts
            "+${pkgs.writeShellScript "find-cert-${serviceName}" ''
            set -euo pipefail
            INSTANCE="$1"

            # Run precedence check
            if ! CERT_INFO=$(${certPrecedenceScript}/bin/konductor-find-best-cert); then
              echo "FATAL: No valid certificate available for konductor-${serviceName}@$INSTANCE" >&2
              exit 1
            fi

            # Write cert info to runtime env file
            echo "$CERT_INFO" > /run/konductor/konductor-${serviceName}@$INSTANCE.cert-env

            # Log which cert tier was selected
            TIER=$(echo "$CERT_INFO" | ${pkgs.gnugrep}/bin/grep CERT_TIER | ${pkgs.coreutils}/bin/cut -d= -f2)
            echo "✓ Using certificate tier: $TIER"
          ''} %i"

            # Step 2: Open firewall port
            # PORT variable from EnvironmentFile (written by konductor-init.service)
            ''+${pkgs.nftables}/bin/nft add rule inet nixos-fw input-allow tcp dport ''${PORT} accept comment \"konductor-${serviceName}@%i-port''${PORT}\"''
          ];

          # Environment files (merged at runtime)
          # EnvironmentFile variables are expanded in ExecStart
          # NOTE: cert-env is optional (-) because it's created by ExecStartPre AFTER
          # systemd loads EnvironmentFile. ExecStart wrapper sources it directly.
          EnvironmentFile = [
            "/var/lib/konductor/env/konductor-${serviceName}@%i.env" # PORT, USER_UID
            "-/run/konductor/konductor-${serviceName}@%i.cert-env" # CERT_PATH, KEY_PATH, CERT_TIER (optional)
          ];

          # Placeholder ExecStart - konductor-init.service drop-in overrides with actual command
          # Using /usr/bin/false ensures service fails if drop-in not generated (fail-safe)
          ExecStart = "${pkgs.coreutils}/bin/false";

          # Close firewall port on stop
          # Parse nftables output to find rule handle by comment, then delete by handle
          # NOTE: %i is passed as $1, PORT as $2 because systemd specifiers aren't expanded inside scripts
          ExecStopPost = "+${pkgs.writeShellScript "cleanup-firewall-${serviceName}" ''
          INSTANCE="$1"
          PORT="$2"
          HANDLE=$(${pkgs.nftables}/bin/nft --handle list chain inet nixos-fw input-allow | \
            ${pkgs.gnugrep}/bin/grep "comment \"konductor-${serviceName}@$INSTANCE-port$PORT\"" | \
            ${pkgs.gnugrep}/bin/grep -o "handle [0-9]*" | \
            ${pkgs.gawk}/bin/awk '{print $2}')
          if [ -n "$HANDLE" ]; then
            ${pkgs.nftables}/bin/nft delete rule inet nixos-fw input-allow handle $HANDLE
          fi
        ''} %i \${PORT}";

          Restart = "on-failure";
          RestartSec = 10;
          NoNewPrivileges = true;
          PrivateTmp = true;
        } // extraServiceConfig;
      };
    };

  # Nix daemon wrapper that sources proxy environment at runtime
  # This is the correct approach for optional runtime proxy configuration (not EnvironmentFile in drop-ins)
  # See: https://github.com/NixOS/nixpkgs (systemd EnvironmentFile + socket-activated services)
  nixDaemonProxyWrapper = pkgs.writeShellScript "nix-daemon-proxy-wrapper" ''
    # Source proxy configuration if it exists (cloud-init runtime config)
    if [ -f /etc/konductor/proxy.env ]; then
      set -a
      . /etc/konductor/proxy.env
      set +a
    fi

    # Execute the real nix-daemon
    exec ${pkgs.nix}/bin/nix-daemon "$@"
  '';

  # Shared NixOS configuration module for both qcow2 image and nixos-rebuild
  # This allows live updates to running VMs via: nixos-rebuild switch --flake .#konductor
  konductorModule = { config, lib, pkgs, modulesPath, ... }: {
    # Import the konductor mount service template, PKI module, home-manager, and QEMU profile
    imports = [
      mountService
      pkiModule
      inputs.home-manager.nixosModules.home-manager
      # QEMU guest profile for virtio drivers and guest agent
      "${modulesPath}/profiles/qemu-guest.nix"
    ];

    # Basic system configuration
    system = {
      # stateVersion from src/lib/versions.nix nixos.stateVersion
      inherit (versions.nixos) stateVersion;

      # Include build dependencies in the system closure (~117GB) so the VM
      # can nixos-rebuild switch and nix build offline in airgapped environments.
      # Future: investigate nix-copy-closure of runtime-only closures (~5-15GB)
      # as a lightweight alternative, but this requires solving build dep caching
      # separately (see OCI.md _oci:vm:sync for prior art).
      # TODO: support separate online (runtime-only ~5-15GB) and offline (~117GB)
      # derivations before re-enabling. Currently disabled to unblock dev iteration.
      includeBuildDependencies = false;

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
      etc.overlay.enable = true;
    };

    # Disable nixpkgs source in registry to prevent 50,000+ file closure bloat
    # nixos/modules/misc/nixpkgs-flake.nix auto-adds nixpkgs to /etc/nix/registry.json
    # which pulls the entire nixpkgs source tree into the system closure.
    #
    # Troubleshoot closure file count:
    #   TOPLEVEL=$(nix build .#nixosConfigurations.konductor.config.system.build.toplevel --no-link --print-out-paths)
    #   for path in $(nix path-info -r $TOPLEVEL); do
    #     printf "%s\t%s\n" "$(fd -t f . "$path" 2>/dev/null | wc -l)" "$path"
    #   done | sort -rn | head -10
    nixpkgs.flake.setFlakeRegistry = false;
    nixpkgs.flake.setNixPath = false;

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
          22 # SSH
          80 # HTTP (forwarded to Envoy Gateway)
          443 # HTTPS (forwarded to Envoy Gateway)
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
    # Dynamic Linker for Pre-compiled Binaries (nix-ld)
    # =====================================================================
    # Enables pre-compiled binaries (VS Code Remote SSH server, language
    # servers, native modules, CLI tools) to find shared libraries on NixOS.
    # Works automatically for all users - no per-user services needed.
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # C/C++ runtime (both for maximum compatibility)
        stdenv.cc.cc.lib # C standard library from stdenv
        gcc-unwrapped.lib # GCC runtime (libstdc++, libgcc_s)

        # Core libraries for VS Code, language servers, and dev tools
        zlib # Compression (VS Code, many tools)
        openssl # SSL/TLS (network tools, language servers)
        icu # Unicode/i18n (VS Code, text processing)
        curl # HTTP client (some extensions, tools)
        sqlite # Embedded database (some extensions)
        ncurses # Terminal UI (TUI tools, debugging)
        readline # Line editing (interactive CLIs)
        libffi # FFI (Python extensions, etc.)
        expat # XML parser (some language servers)
        xz # LZMA compression (archives)
        bzip2 # Compression (archives)
      ];
    };

    # =====================================================================
    # FHS Compatibility Layer (System-Wide)
    # =====================================================================
    # Provides FHS compatibility for ALL pre-compiled binaries, not just VS Code.
    # This is a layered defense approach:
    #
    # Layer 1: FHS Library Symlinks (file existence checks)
    #   - Creates /lib/libstdc++.so.6, /lib/libgcc_s.so.1
    #   - Satisfies binaries that check for library file existence
    #
    # Layer 2: ldconfig Wrapper (pre-flight checks)
    #   - Provides working `ldconfig -p` output
    #   - NixOS glibc's ldconfig errors because it looks for ld.so.cache
    #     relative to its PREFIX in nix store, not /etc
    #   - Uses meta.priority to shadow glibc's ldconfig
    #
    # Layer 3: nix-ld (runtime library loading) - configured above
    #
    # Layer 4: buildFHSEnv + node patching - for downloaded binaries
    #
    # This approach helps ALL FHS-expecting software, not just VS Code.
    # =====================================================================

    # Layer 1: FHS Library Symlinks
    system.activationScripts.fhs-compat = ''
      # Create FHS library directories
      mkdir -p /lib /lib64

      # Symlink core C++ runtime libraries to FHS paths
      # These satisfy file existence checks that pre-compiled binaries perform
      ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 /lib/libstdc++.so.6
      ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 /lib/libstdc++.so
      ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 /lib/libgcc_s.so.1

      # Symlink glibc for completeness
      ln -sf ${pkgs.glibc}/lib/libc.so.6 /lib/libc.so.6

      # Symlink dynamic linker to /lib (VS Code checks both /lib and /lib64)
      ln -sf /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2

      # VS Code CLI checks /sbin/ldconfig specifically (found via binary analysis)
      mkdir -p /sbin
      ln -sf /run/current-system/sw/bin/ldconfig /sbin/ldconfig
    '';

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
    # MOTD and Users
    # =====================================================================
    # Dynamic MOTD generated by konductor.service on boot.
    # Shows provenance identity and verification status.
    # Designed to be informative for newcomers, unimposing for daily users.
    users = {
      motdFile = "/run/konductor/motd";

      # All users in 'kc2' group (GID 1001) for shared directory access
      # Group must be defined BEFORE users reference it in extraGroups
      groups.kc2 = {
        gid = 1001;
        members = [ "kc2" "kc2admin" "runner" "forgejo" ];
      };
      groups.forgejo = {
        gid = users.forgejo.gid;
      };

      users = {
        kc2 = {
          isNormalUser = true;
          inherit (users.kc2) uid home;
          description = users.kc2.gecos;
          # Linger: keep systemd --user alive across SSH sessions so Open Sesame
          # daemons persist. SSH agent socket is refreshed via profile.d hook.
          linger = true;
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
          linger = true;
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
        # Forgejo server user — reserves UID 1004 so cloud-init
        # additional users (1005+) get their expected UIDs.
        forgejo = {
          isNormalUser = true;
          inherit (users.forgejo) uid home;
          description = users.forgejo.gecos;
          extraGroups = [
            "kc2"
            "forgejo"
            "docker"
          ];
        };
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
          # Source proxy configuration for all shell types (login, non-login, scripts)
          # profile.d only runs for login shells; this ensures non-login shells
          # (e.g., subshells, direnv, nix develop) also inherit proxy vars.
          # The file uses KEY=VALUE format (systemd EnvironmentFile compatible),
          # so set -a is needed to auto-export.
          if [ -f /etc/konductor/proxy.env ]; then
            set -a
            . /etc/konductor/proxy.env
            set +a
          fi
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
      # Layer 2: ldconfig Wrapper - forcibly replace glibc's ldconfig
      # meta.priority doesn't work because glibc is a dependency, not a systemPackage
      # environment.extraSetup runs in postBuild and can replace the symlink
      extraSetup = ''
        rm -f $out/bin/ldconfig
        ln -s ${vscodeLdconfigWrapper}/bin/ldconfig $out/bin/ldconfig
      '';

      # Don't include default packages (nano, perl, rsync, strace)
      defaultPackages = lib.mkForce [ ];

      # Session variables (PAM-level - available to all contexts including systemd services)
      # Uses @{HOME} syntax for PAM variable expansion
      sessionVariables = {
        # CI environment marker
        CI = "true";
        # Hermetic bash configuration (from devshell)
        inherit (konductorConfig.shell.bash.env) KONDUCTOR_BASHRC KONDUCTOR_INPUTRC;
        # Atuin shell history (config + bash-preexec for hooks)
        inherit (konductorConfig.shell.atuin.env) ATUIN_CONFIG_DIR KONDUCTOR_PREEXEC_PATH;
        # Language paths (PAM @{HOME} expansion)
        GOPATH = "@{HOME}/go";
        CARGO_HOME = "@{HOME}/.cargo";
        PNPM_HOME = "@{HOME}/.local/share/pnpm";
        # OVMF EFI firmware paths for QEMU (from konductor.env)
        OVMF_CODE = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
        OVMF_VARS = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
        # Docker buildkit
        DOCKER_BUILDKIT = "1";
        # Library path for CI runner (libstdc++ for grpcio/pulumi, xz/zstd for nix)
        LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.xz pkgs.zstd ]}";
      };

      # /etc/skel - Shell Configuration (copied to new user home dirs)
      # Same shell experience as devshell and OCI container
      # Uses canonical config from src/config/shell/ (SSOT)
      etc = {
        "skel/.bashrc".text = konductorConfig.shell.bash.bashrcContent;
        "skel/.bash_profile".text = shellContent.bashProfileContent;
        "skel/.inputrc".text = shellContent.inputrcContent;
        # Note: .gitconfig is NOT in skel - git config is at system level via programs.git
        "skel/.config/starship.toml".text = konductorConfig.shell.starship.configContent;
        "skel/.config/atuin/config.toml".text = konductorConfig.shell.atuin.configContent;

        # /etc/skel/.envrc - for project .env files only (packages pre-installed)
        "skel/.envrc".text = ''
          # Konductor VM - all packages pre-installed system-wide
          # This .envrc is for project-specific env vars only
          dotenv_if_exists .env
          dotenv_if_exists "$HOME/.env"
        '';

        # /etc/skel/.config/pds - Open Sesame headless config
        # Minimal config for headless mode (no WM keybindings)
        "skel/.config/pds/config.toml".text = ''
          config_version = 3

          [global]
          default_profile = "default"
          [global.ipc]
          [global.logging]

          [profiles.default]
          name = "default"
          [profiles.default.wm]

          [crypto]
          [agents]
          [extensions]
        '';

        # Note: direnv whitelist is in /etc/direnv/direnv.toml via programs.direnv.settings
        # No user-level direnv.toml needed since NixOS sets DIRENV_CONFIG=/etc/direnv

        # /etc/profile.d/konductor-ssh-agent.sh - propagate forwarded SSH agent
        # to systemd user services via stable symlink + environment import.
        # Runs on every interactive SSH login. Idempotent.
        "profile.d/konductor-ssh-agent.sh".text = ''
          # Propagate SSH agent forwarding to systemd user services.
          # Creates a stable symlink at ~/.ssh/agent.sock so services using
          # a fixed SSH_AUTH_SOCK path can reach the forwarded agent even
          # after session rotation.
          if [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
            # Create stable symlink (updated on each login)
            mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
            ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"

            # Override SSH_AUTH_SOCK for this session to use the stable path
            export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

            # Write EnvironmentFile for Open Sesame systemd user services
            mkdir -p "$HOME/.config/pds" 2>/dev/null || true
            printf 'SSH_AUTH_SOCK=%s/.ssh/agent.sock\n' "$HOME" > "$HOME/.config/pds/ssh-agent.env"

            # Import into systemd user manager (affects newly started services)
            if command -v systemctl >/dev/null 2>&1; then
              systemctl --user import-environment SSH_AUTH_SOCK 2>/dev/null || true
            fi
          fi
        '';

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
          if [ ! -f "$HOME/.config/pds/config.toml" ] && [ -f /etc/skel/.config/pds/config.toml ]; then
            mkdir -p "$HOME/.config/pds"
            cp -L /etc/skel/.config/pds/config.toml "$HOME/.config/pds/"
          fi
          # Open Sesame runtime directories (needed by systemd user services)
          mkdir -p "$HOME/.config/pds" "$HOME/.cache/open-sesame" 2>/dev/null || true
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

        # PKI Trust Configuration (Git CA Trust)
        # Configure global git settings for all users
        # Points directly to mounted hypervisor CA (available at runtime)
        # If CA not mounted, git will fall back to system CA bundle
        "gitconfig".text = ''
          [http]
            sslCAInfo = /mnt/pki/ca.crt
          [safe]
            directory = /workspace
        '';

        # Vendored Flake Input Sources (Baked into Image)
        # Every flake input's outPath is referenced here, which pulls it into
        # the system closure. nixos-install copies them to the image's /nix/store.
        # /etc/konductor/input-sources.env maps input names to store paths.
        "konductor/input-sources.env".text =
          let
            # Filter to inputs that have outPath (excludes 'self' and non-flake attrs)
            inputsWithPath = lib.filterAttrs
              (name: input: name != "self" && (input ? outPath || (builtins.isAttrs input && input ? sourceInfo)))
              inputs;
          in
          lib.concatStringsSep "\n"
            (
              lib.mapAttrsToList (name: input: "${name}=${input.outPath or input}")
                inputsWithPath
            ) + "\n";
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
          yj # TOML to JSON converter (for konductor-init.service)
          yq-go # YAML/TOML/JSON processor
        ])
        # Open Sesame headless daemons (profile, secrets, launcher, snippets)
        ++ [ openSesamePkg ]
        # Certificate precedence detection for multi-user services
        ++ [ certPrecedenceScript ]
        # FHS compatibility: ldconfig wrapper with high priority
        # Shadows glibc's ldconfig to satisfy pre-flight checks
        ++ [
          (vscodeLdconfigWrapper.overrideAttrs (old: {
            meta = (old.meta or { }) // {
              # Lower number = higher priority = appears first in PATH
              # glibc has default priority (0), so -10 ensures we win
              priority = -10;
            };
          }))
        ]
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
        "d /run/konductor 0755 root root -"  # cert-env files for per-user services
      ];

      # =====================================================================
      # Open Sesame — system-wide user services (headless mode)
      # =====================================================================
      # NixOS-level systemd.user.* puts units in /etc/systemd/user/ which
      # applies to ALL users, including cloud-init dynamic users that are
      # not managed by home-manager. For built-in HM users, /etc/systemd/user/
      # takes precedence over ~/.config/systemd/user/ (harmless shadow).

      user.targets.open-sesame = {
        unitConfig = {
          Description = "Open Sesame Headless Suite";
          Documentation = "https://github.com/scopecreep-zip/open-sesame";
        };
        wantedBy = [ "default.target" ];
      };

      user.services.open-sesame-profile = {
        unitConfig = {
          Description = "Open Sesame profile daemon (IPC bus)";
          Documentation = "https://github.com/scopecreep-zip/open-sesame";
          PartOf = [ "open-sesame.target" ];
        };
        serviceConfig = {
          Type = "notify";
          ExecStart = "${openSesamePkg}/bin/daemon-profile";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 5;
          WatchdogSec = 30;
          NoNewPrivileges = true;
          ProtectHome = "read-only";
          ProtectSystem = "strict";
          ReadWritePaths = [ "%t/pds" "%h/.config/pds" ];
          LimitNOFILE = 4096;
          MemoryMax = "128M";
          Environment = [ "RUST_LOG=info" ];
          EnvironmentFile = [ "-%h/.config/pds/ssh-agent.env" ];
        };
        wantedBy = [ "open-sesame.target" ];
      };

      user.services.open-sesame-secrets = {
        unitConfig = {
          Description = "Open Sesame secrets daemon";
          Documentation = "https://github.com/scopecreep-zip/open-sesame";
          Requires = [ "open-sesame-profile.service" ];
          After = [ "open-sesame-profile.service" ];
          PartOf = [ "open-sesame.target" ];
        };
        serviceConfig = {
          Type = "notify";
          ExecStart = "${openSesamePkg}/bin/daemon-secrets";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 5;
          WatchdogSec = 30;
          NoNewPrivileges = true;
          PrivateNetwork = true;
          ProtectHome = "read-only";
          ProtectSystem = "strict";
          ReadWritePaths = [ "%t/pds" "%h/.config/pds" ];
          LimitNOFILE = 1024;
          LimitMEMLOCK = "64M";
          MemoryMax = "256M";
          Environment = [ "RUST_LOG=info" ];
        };
        wantedBy = [ "open-sesame.target" ];
      };

      user.services.open-sesame-launcher = {
        unitConfig = {
          Description = "Open Sesame launcher daemon";
          Documentation = "https://github.com/scopecreep-zip/open-sesame";
          Requires = [ "open-sesame-profile.service" ];
          After = [ "open-sesame-profile.service" ];
          PartOf = [ "open-sesame.target" ];
        };
        serviceConfig = {
          Type = "notify";
          ExecStart = "${openSesamePkg}/bin/daemon-launcher";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 5;
          WatchdogSec = 30;
          NoNewPrivileges = true;
          ProtectHome = "read-only";
          ProtectSystem = "strict";
          ReadWritePaths = [ "%t/pds" "%h/.config/pds" ];
          LimitNOFILE = 4096;
          MemoryMax = "128M";
          Environment = [ "RUST_LOG=info" ];
        };
        wantedBy = [ "open-sesame.target" ];
      };

      user.services.open-sesame-snippets = {
        unitConfig = {
          Description = "Open Sesame snippets daemon";
          Documentation = "https://github.com/scopecreep-zip/open-sesame";
          Requires = [ "open-sesame-profile.service" ];
          After = [ "open-sesame-profile.service" ];
          PartOf = [ "open-sesame.target" ];
        };
        serviceConfig = {
          Type = "notify";
          ExecStart = "${openSesamePkg}/bin/daemon-snippets";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 5;
          WatchdogSec = 30;
          NoNewPrivileges = true;
          ProtectHome = "read-only";
          ProtectSystem = "strict";
          ReadWritePaths = [ "%t/pds" ];
          LimitNOFILE = 4096;
          MemoryMax = "128M";
          Environment = [ "RUST_LOG=info" ];
        };
        wantedBy = [ "open-sesame.target" ];
      };

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
              echo "  · kernel: $(uname -r)"

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
              if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
                TRUST_HASH=$(sha256sum /etc/ssl/certs/ca-certificates.crt | cut -d' ' -f1)
                echo "  · trust_store_sha256: ''${TRUST_HASH:0:16}...''${TRUST_HASH: -16}"
              fi
              echo "└─────────────────────────────────────────────────────────────────────────────┘"

              # ─────────────────────────────────────────────────────────────────────
              # MACHINE-READABLE PROVENANCE
              # ─────────────────────────────────────────────────────────────────────
              if [ -f /.konductor ]; then
                STRICT_BOOL="false"
                [ "''${STRICT}" = "true" ] && STRICT_BOOL="true"
                GIT_BRANCH=$(sed -n 's/^git_branch = "\(.*\)"$/\1/p' /.konductor)
                NIX_HASH=$(sed -n 's/^nix_hash = "\(.*\)"$/\1/p' /.konductor)
                echo "PROVENANCE_JSON: $(jq -n \
                  --arg gc "''${GIT_COMMIT}" \
                  --arg gb "''${GIT_BRANCH}" \
                  --arg nd "''${NIX_DRV}" \
                  --arg nh "''${NIX_HASH}" \
                  --arg fl "''${EXPECTED_LOCK}" \
                  --argjson strict "''${STRICT_BOOL}" \
                  --argjson errors "''${ERRORS}" \
                  --argjson warnings "''${WARNINGS}" \
                  --arg kernel "$(uname -r)" \
                  '{git_commit:''$gc, git_branch:''$gb, nix_drv:''$nd, nix_hash:''$nh, flake_lock_sha256:''$fl, strict:''$strict, errors:''$errors, warnings:''$warnings, kernel:''$kernel}')"
              fi

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
        #   - docker: For pulling container images
        #
        # NOTE: nix-daemon proxy is handled via wrapper script (see nixDaemonProxyWrapper)
        # because socket-activated services don't reliably load EnvironmentFile from runtime drop-ins.
        #
        # CRITICAL ORDERING:
        #   - MUST run AFTER cloud-init.service (when write_files completes)
        #   - MUST run BEFORE docker to configure it on first boot
        #   - Explicitly restarts service to handle case where it started early
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
          description = "Configure proxy for Docker and Nix from cloud-init";
          # Wait for cloud-init to complete (when proxy.env is written)
          after = [ "cloud-init.service" ];
          # Start before docker and nix-daemon (for ordering on subsequent boots)
          before = [ "docker.service" "nix-daemon.service" ];
          # Activate via multi-user target (not wantedBy the service itself)
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            ConditionPathExists = "/etc/konductor/proxy.env";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "setup-docker-proxy" ''
              set -euo pipefail
              PROXY_ENV="/etc/konductor/proxy.env"

              echo "Configuring Docker proxy from $PROXY_ENV"

              # Configure Docker daemon proxy
              DOCKER_DROPIN_DIR="/run/systemd/system/docker.service.d"
              mkdir -p "$DOCKER_DROPIN_DIR"
              cat > "$DOCKER_DROPIN_DIR/proxy.conf" << EOF
              [Service]
              EnvironmentFile=$PROXY_ENV
              EOF
              echo "  ✓ docker proxy drop-in created"

              # Reload systemd to pick up the drop-in
              systemctl daemon-reload
              echo "  ✓ systemd daemon reloaded"

              # Restart docker to apply proxy settings (ONLY if already active)
              # Before= ordering means service is blocked from starting until we complete.
              # On clean boot: service not active → no restart needed → drop-in applies on first start
              # On early activation race: service became active early → restart applies config
              echo "Checking docker for proxy configuration apply..."

              # Only restart docker if it's currently active (not waiting in job queue)
              if systemctl is-active --quiet docker.service 2>/dev/null; then
                systemctl restart docker.service && echo "  ✓ docker restarted (was active)"
              else
                echo "  · docker not yet active (will use proxy config on first start)"
              fi

              # Restart nix-daemon so the proxy wrapper re-sources proxy.env
              # The nix-daemon is socket-activated and may have started before
              # cloud-init wrote proxy.env. The wrapper script sources the file
              # at daemon start time, so a restart ensures it picks up the config.
              if systemctl is-active --quiet nix-daemon.service 2>/dev/null; then
                systemctl restart nix-daemon.service && echo "  ✓ nix-daemon restarted (was active)"
              else
                echo "  · nix-daemon not yet active (will use proxy config on first start)"
              fi

              echo "Proxy configuration applied to Docker and Nix"
            '';
          };
        };

        # Override nix-daemon to use proxy wrapper script
        # Socket-activated services don't reliably load EnvironmentFile from runtime drop-ins,
        # so we use a wrapper that sources /etc/konductor/proxy.env at execution time.
        # See: https://github.com/NixOS/nixpkgs (systemd documentation)
        nix-daemon = {
          serviceConfig = {
            # Override ExecStart with our proxy wrapper
            # Empty string "" clears previous ExecStart directives
            ExecStart = lib.mkForce [ "" "${nixDaemonProxyWrapper}" ];
          };
        };

        # =====================================================================
        # Host Nix Store Substituter (conditional on virtiofs)
        # =====================================================================
        # Attempts to mount virtiofs "nixstore" tag. On success, writes
        # /etc/nix/host-store.conf so nix picks up the local substituter.
        # On standalone VMs (no virtiofs), mount fails → no conf → nix
        # never sees the substituter → zero overhead, no fatal abort.
        konductor-host-nix-store = {
          description = "Activate host nix store substituter if virtiofs available";
          after = [ "local-fs.target" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig.ConditionPathIsMountPoint = "!/mnt/host-nix";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "activate-host-nix-store" ''
              set -euo pipefail

              ${pkgs.coreutils}/bin/mkdir -p /mnt/host-nix

              # Attempt virtiofs mount — exits non-zero if no device
              ${pkgs.util-linux}/bin/mount -t virtiofs -o ro nixstore /mnt/host-nix 2>/dev/null \
                || { echo "host-nix-store: no virtiofs device, standalone mode"; exit 0; }

              # Mounted — verify nix DB exists
              ${pkgs.coreutils}/bin/test -f /mnt/host-nix/nix/var/nix/db/db.sqlite \
                || { echo "host-nix-store: virtiofs mounted but no nix DB, unmounting";
                     ${pkgs.util-linux}/bin/umount /mnt/host-nix; exit 0; }

              # DB present — activate substituter and restart nix-daemon
              printf '%s\n' \
                'extra-substituters = local?root=/mnt/host-nix&read-only=true' \
                'extra-trusted-substituters = local?root=/mnt/host-nix&read-only=true' \
                > /etc/nix/host-store.conf
              echo "host-nix-store: activated local substituter"
              ${pkgs.systemd}/bin/systemctl restart nix-daemon.service
            '';
          };
        };

        # =====================================================================
        # Forgejo Runner Service
        # =====================================================================
        # Runs Forgejo Actions runner daemon after cloud-init registration.
        # Cloud-init Phase 6 creates .runner file, Phase 7 starts this service.
        #
        # PKI trust is handled by konductor-pki-trust.service (pki.nix),
        # which installs the hypervisor CA to the system trust store.
        # Go's TLS uses the system trust store by default.
        forgejo-runner = {
          description = "Forgejo Actions Runner";
          # Boot ordering: systemd auto-starts via wantedBy, but ConditionPathExists
          # gates on .runner file (created by cloud-init Phase 6 registration).
          # On first boot: condition fails → skipped → cloud-init Phase 7 starts it.
          # On subsequent boots: condition passes → systemd auto-starts it.
          # ExecStartPre polls Forgejo API to handle server not yet reachable.
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
          # Generous restart rate limit: runner must survive long CI jobs
          # and recover from transient Forgejo outages (scale-to-zero, redeploys)
          startLimitIntervalSec = 300;
          startLimitBurst = 10;
          # Don't start until cloud-init Phase 6 creates the .runner registration file
          unitConfig.ConditionPathExists = "/home/runner/.config/forgejo-runner/.runner";
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
              # NixOS /etc/ssl/certs is immutable; konductor-pki-trust writes extended bundle
              "SSL_CERT_FILE=/etc/konductor/pki/bundle/ca-bundle.crt"
            ];
            # Wait for Forgejo to be reachable before starting runner daemon.
            # Handles race condition: runner starts before Forgejo is deployed
            # (scale-to-zero, fresh platform deploy, pod restarts).
            # Retries every 5s for up to 5 minutes.
            ExecStartPre = pkgs.writeShellScript "wait-for-forgejo" ''
              URL=$(cat /etc/konductor/forgejo-runner/url 2>/dev/null)
              if [ -z "$URL" ]; then
                echo "forgejo-runner: no server URL configured, skipping readiness check"
                exit 0
              fi
              echo "forgejo-runner: waiting for $URL to become reachable..."
              attempts=0
              max_attempts=60
              while [ "$attempts" -lt "$max_attempts" ]; do
                if ${pkgs.curl}/bin/curl \
                  --silent --fail --max-time 5 \
                  --cacert /etc/konductor/pki/bundle/ca-bundle.crt \
                  -o /dev/null "$URL/api/v1/version" 2>/dev/null; then
                  echo "forgejo-runner: $URL is reachable"
                  exit 0
                fi
                attempts=$((attempts + 1))
                echo "forgejo-runner: attempt $attempts/$max_attempts - $URL not ready, retrying in 5s..."
                sleep 5
              done
              echo "forgejo-runner: $URL not reachable after $((max_attempts * 5))s, starting anyway"
              exit 0
            '';
            ExecStart = "${programs.forgejo.runner}/bin/forgejo-runner daemon --config /home/runner/.config/forgejo-runner/config.yaml";
            Restart = "always";
            RestartSec = 15;
          };
        };

        # =====================================================================
        # Forgejo Runner Registration Retry Service
        # =====================================================================
        # Defense in depth: if cloud-init registration fails (Forgejo not ready),
        # the timer below retries every 30s until .runner file is created.
        # Once registered, forgejo-runner.service is started and timer stops.
        forgejo-runner-register = {
          description = "Retry Forgejo Runner Registration";
          after = [
            "network-online.target"
            "konductor-pki-trust.service"
          ];
          wants = [ "network-online.target" ];
          # Do NOT add wantedBy — started only by the timer
          unitConfig.ConditionPathExists = "!/home/runner/.config/forgejo-runner/.runner";
          serviceConfig = {
            Type = "oneshot";
            User = "runner";
            Group = "users";
            Environment = [
              "HOME=/home/runner"
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
              "SSL_CERT_FILE=/etc/konductor/pki/bundle/ca-bundle.crt"
            ];
            ExecStart = pkgs.writeShellScript "forgejo-runner-register-retry" ''
              CONFIG_DIR="/home/runner/.config/forgejo-runner"
              RUNNER_FILE="$CONFIG_DIR/.runner"

              # Skip if already registered
              if [ -f "$RUNNER_FILE" ]; then
                echo "forgejo-runner-register: already registered, nothing to do"
                exit 0
              fi

              SECRET_FILE="/etc/konductor/forgejo-runner/secret"
              URL_FILE="/etc/konductor/forgejo-runner/url"

              if [ ! -f "$SECRET_FILE" ] || [ ! -f "$URL_FILE" ]; then
                echo "forgejo-runner-register: secret or url not configured, skipping"
                exit 1
              fi

              SECRET=$(${pkgs.coreutils}/bin/cat "$SECRET_FILE")
              URL=$(${pkgs.coreutils}/bin/cat "$URL_FILE")
              NAME=$(${pkgs.hostname}/bin/hostname)

              echo "forgejo-runner-register: attempting registration against $URL..."
              ${pkgs.coreutils}/bin/mkdir -p "$CONFIG_DIR"

              if ${programs.forgejo.runner}/bin/forgejo-runner \
                --config "$CONFIG_DIR/config.yaml" \
                create-runner-file \
                --secret "$SECRET" \
                --instance "$URL" \
                --name "$NAME" \
                --connect; then
                echo "forgejo-runner-register: registration succeeded, starting runner"
                # Start the runner service now that .runner exists
                /run/current-system/sw/bin/systemctl start forgejo-runner.service || true
                # Stop the retry timer — no longer needed
                /run/current-system/sw/bin/systemctl stop forgejo-runner-register.timer || true
                exit 0
              else
                echo "forgejo-runner-register: registration failed, timer will retry"
                exit 1
              fi
            '';
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
        # NOTE: afterServices uses default (no konductor-init.service to avoid circular dep)
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
          Restart = "no"; # Don't restart on failure - requires intervention
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
        # VS Code Remote SSH Fix Service (per-user watcher)
        # =====================================================================
        # Patches VS Code Remote SSH server node binaries to work on NixOS.
        # VS Code downloads pre-compiled node that expects FHS paths.
        # This service:
        # 1. Patches existing VS Code server installations on startup
        # 2. Watches for new installations and patches them automatically
        #
        # Uses buildFHSEnv wrapper (vscodeServerFHS) that provides nodejs
        # with all required libraries in an FHS-compatible environment.
        #
        # Based on: https://github.com/nix-community/nixos-vscode-server
        # Adapted for konductor's multi-user systemd template architecture.
        # =====================================================================
        "konductor-vscode-fix@" = {
          description = "VS Code Remote SSH Fix for %i";
          documentation = [ "https://github.com/nix-community/nixos-vscode-server" ];
          after = [ "network.target" ];

          path = with pkgs; [ inotify-tools coreutils findutils ];

          serviceConfig = {
            Type = "simple";
            User = "%i";
            Group = "users";
            Restart = "on-failure";
            RestartSec = 5;

            # Patch any existing VS Code server installations before watching
            ExecStartPre = "${vscodeServerPatchScript} /home/%i";

            # Watch for new VS Code server installations and patch them
            ExecStart = "${vscodeServerWatchScript} %i";
          };
        };
      }
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
                                # Cert env is created by ExecStartPre, sourced by ExecStart wrapper
                                CERT_ENV_FILE="/run/konductor/konductor-''${svc_name}@''${username}.cert-env"
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
                            [Unit]
                            After=konductor-mount@home-''${USER_UID}.service
                            Wants=konductor-mount@home-''${USER_UID}.service

                            [Service]
                            EnvironmentFile=$ENV_FILE

                            # Override ExecStart with calculated port
                            # NOTE: ExecStart sources cert-env because EnvironmentFile is loaded
                            # BEFORE ExecStartPre (which creates cert-env). Shell wrapper pattern.
                            ExecStart=
              EOF

                                # Service-specific ExecStart overrides
                                # All services use multi-tier certificate precedence (cluster→hypervisor→self-signed)
                                # Certificate variables (CERT_PATH, KEY_PATH) come from cert-env file
                                # which is created by base unit's ExecStartPre and sourced by ExecStart wrapper
                                case "$svc_name" in
                                  ttyd)
                                    cat >> "$DROPIN_PATH/50-config.conf" << EOF
              ExecStart=/bin/sh -c '. $CERT_ENV_FILE && exec ${programs.ttyd.wrapped}/bin/ttyd-konductor -p \''${PORT} -S -C \$CERT_PATH -K \$KEY_PATH -- ${pkgs.bashInteractive}/bin/bash'
              EOF
                                    ;;
                                  restty)
                                    cat >> "$DROPIN_PATH/50-config.conf" << EOF
              ExecStart=/bin/sh -c '. $CERT_ENV_FILE && exec ${(import ../programs/restty-web { inherit pkgs lib; }).server}/bin/restty-web-server --port \''${PORT} --cert \$CERT_PATH --key \$KEY_PATH --writable --working-directory /workspace'
              EOF
                                    ;;
                                  ghostty)
                                    cat >> "$DROPIN_PATH/50-config.conf" << EOF
              ExecStart=/bin/sh -c '. $CERT_ENV_FILE && exec ${(import ../programs/ghostty-web { inherit pkgs lib; }).server}/bin/ghostty-web-server --port \''${PORT} --cert \$CERT_PATH --key \$KEY_PATH --writable --working-directory /workspace'
              EOF
                                    ;;
                                  vscode)
                                    cat >> "$DROPIN_PATH/50-config.conf" << EOF
              ExecStartPre=/bin/sh -c 'mkdir -p /home/''${username}/.local/share/code-server/extensions && for ext in ${vscodeExtensionsDir}/share/vscode/extensions/*; do ln -sfn "\$ext" /home/''${username}/.local/share/code-server/extensions/; done'
              ExecStartPre=/bin/sh -c 'mkdir -p /home/''${username}/.local/share/code-server/User && test -f /home/''${username}/.local/share/code-server/User/settings.json || cp ${vscodeDefaultSettings} /home/''${username}/.local/share/code-server/User/settings.json'
              ExecStart=/bin/sh -c '. $CERT_ENV_FILE && exec ${pkgs.code-server}/bin/code-server --bind-addr 0.0.0.0:\''${PORT} --user-data-dir /home/''${username}/.local/share/code-server --extensions-dir /home/''${username}/.local/share/code-server/extensions --auth none --cert \$CERT_PATH --cert-key \$KEY_PATH --disable-telemetry --disable-update-check --disable-getting-started-override /workspace'
              EOF
                                    # Also enable VS Code Remote SSH fix service for this user
                                    # This patches VS Code's downloaded node binary to work on NixOS
                                    # See: konductor-vscode-fix@.service and vscodeServerFHS/vscodeServerPatchScript
                                    echo "konductor-vscode-fix@''${username}.service" >> "$STATE_DIR/enabled.list.new"
                                    echo "    ✓ VS Code Remote SSH fix: konductor-vscode-fix@''${username}.service"
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
              yj # TOML to JSON converter
              yq-go # YAML/TOML/JSON processor
              jq # JSON query processor
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

    # =====================================================================
    # Forgejo Runner Registration Retry Timer
    # =====================================================================
    # Periodically triggers forgejo-runner-register.service to retry
    # runner registration if .runner file doesn't exist yet.
    # ConditionPathExists prevents activation once registration succeeds.
    systemd.timers.forgejo-runner-register = {
      description = "Retry Forgejo Runner Registration Timer";
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionPathExists = "!/home/runner/.config/forgejo-runner/.runner";
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
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
          # Explicit: permit agent forwarding (default is yes)
          AllowAgentForwarding = true;
          # Clean up stale StreamLocalForward sockets on reconnect
          StreamLocalBindUnlink = true;
        };
        # Deny agent forwarding for service accounts (CI runner, forge server).
        # These accounts should never proxy signing authority from a user's keys.
        extraConfig = ''
          Match User runner
            AllowAgentForwarding no
          Match User forgejo
            AllowAgentForwarding no
        '';
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
        network.enable = true; # Enables systemd-networkd integration

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
      diskSize = lib.mkDefault (150 * 1024); # 150GB (includes build dependencies for airgap self-rebuild)

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
      # Enable partition growing for cloud deployments
      growPartition = true;

      # Use latest kernel for best hardware support and security
      kernelPackages = pkgs.linuxPackages_latest;

      # =====================================================================
      # Bootloader Configuration (EFI)
      # =====================================================================
      # Required for nixosConfigurations (nixos-rebuild on running VMs).
      # The qcow-efi format provides this automatically for image builds,
      # but nixpkgs.lib.nixosSystem needs explicit bootloader config.
      loader = {
        timeout = 0; # Skip boot menu for faster boot
        grub = {
          enable = true;
          device = "nodev"; # EFI doesn't use a specific device
          efiSupport = true;
          efiInstallAsRemovable = true; # Works without NVRAM variables
        };
        efi = {
          canTouchEfiVariables = false; # Don't modify NVRAM (safer for VMs)
          efiSysMountPoint = "/boot";
        };
      };

      # =====================================================================
      # Storage Optimization for Ceph RBD Block Devices
      # =====================================================================
      # Aligned for 4KB Ceph BlueStore allocation (bluestore_min_alloc_size_ssd)
      # See: Pulumi.optiplex-rook-ceph.yaml ceph_config_override

      # I/O scheduler: none for virtio-blk (Ceph handles its own scheduling)
      # Serial console for hypervisor log capture (KubeVirt, libvirt, QEMU dev)
      # NOTE: Linux uses LAST console= as primary stdout. ttyS0 must be last so
      # serial captures all kernel/systemd output (needed for -display none builds
      # and KubeVirt serial console). kbd_mode warning on serial is harmless.
      kernelParams = [
        "console=tty0" # VGA console (also receives output)
        "console=ttyS0,115200" # Serial console (primary — receives all output)
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
          "virtiofs"
          "9p"
          "9pnet_virtio"
        ];
        # NOTE: /etc/mtab symlink is handled automatically by systemd initrd
        # (previously used postDeviceCommands which is incompatible with systemd initrd)
      };
    };

    # =====================================================================
    # Filesystem Configuration
    # =====================================================================
    # Required for nixosConfigurations (nixos-rebuild on running VMs).
    # Uses labels set by qcow-efi format during image creation.
    # Options optimized for Ceph RBD block devices.
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true; # Grow partition on first boot (cloud-init growpart)
        options = [
          "noatime" # Reduce metadata writes
          "nodiratime" # Reduce directory access time updates
          "discard" # TRIM/unmap for thin provisioning
          "commit=60" # Increase journal commit interval (seconds)
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };

      # =====================================================================
      # Host Nix Store (Read-Only Substituter for Build & Fleet Acceleration)
      # =====================================================================
      # A read-only host nix store can be mounted via virtiofs at /mnt/host-nix.
      # virtiofsd shares the host's /nix directory. The mount point is chosen
      # so that local?root=/mnt/host-nix finds the store at /mnt/host-nix/nix/store
      # and the DB at /mnt/host-nix/nix/var/nix/db — matching nix's convention
      # of root + /nix/store and root + /nix/var/nix.
      #
      # Nix opens this as a read-only local store (experimental feature
      # read-only-local-store) and uses it as a substituter. nixos-rebuild and
      # nix-build copy needed paths into the VM's real /nix/store on disk.
      #
      # Architecture:
      #   /mnt/host-nix/nix/store (virtiofs, ro) ──► nix substituter
      #   /mnt/host-nix/nix/var/nix/db (virtiofs, ro) ──► path metadata
      #   /nix/store (real on-disk ext4) ──► nix writes here directly
      #
      # Use cases:
      #   CI build:   host shares its /nix via virtiofs for cache hits
      #   Deploy:     many VMs share one read-only host nix (single builder,
      #               many consumers) for efficient fleet-wide nix operations
      #   Standalone: no host mount present — substituter silently fails,
      #               nix falls back to cache.nixos.org
      #
      # Paths are always materialized on the real local disk. The image boots
      # standalone without any host mounts.
      # Host nix store virtiofs mount — deploy mode only.
      # With automount, every substituter query triggers a mount attempt,
      # which cycles ENODEV on VMs without the virtiofs device attached.
      # Instead: noauto + nofail, and cloud-init/systemd mounts explicitly
      # only when the virtiofs tag "nixstore" is present.
      "/mnt/host-nix" = {
        device = "nixstore";
        fsType = "virtiofs";
        options = [
          "ro"
          "nofail"  # Don't fail boot if device absent (standalone)
          "noauto"  # Don't mount at boot — explicit mount only
        ];
        neededForBoot = false;
      };
    };


    # =====================================================================
    # QCOW2 Image Builder (Fast - no cptofs)
    # =====================================================================
    # Build QCOW2 image using our custom fast builder that copies files
    # INSIDE the VM via virtiofs instead of using slow cptofs (LKL).
    #
    # Standard make-disk-image.nix uses cptofs which is extremely slow:
    # - Runs Linux kernel in userspace (LKL)
    # - 4KB buffer, single-threaded, ~9 syscalls per file
    # - 100k files = 40+ minutes
    #
    # Our fast builder:
    # - Real Linux kernel with virtiofs-shared /nix/store
    # - Native ext4 I/O with proper caching
    # - nixos-install for proper system setup
    # - 5-10x faster for large closures
    system.build.image = import ./make-disk-image-fast.nix {
      inherit lib config pkgs;
      inherit (config.virtualisation) diskSize;
      format = "qcow2";
      partitionTableType = "efi";
      memSize = 16384;
      cpuCount = 4; # Cap inner VM cores to avoid starving KubeVirt/host
      # Bake CI devshell closure into image so `nix develop #ci` is instant
      additionalPaths = [ devshells.ci ];
    };

    # Nix configuration
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "read-only-local-store" # Required for host store substituter on read-only virtiofs
        ];
        auto-optimise-store = true;
        accept-flake-config = true;
        download-buffer-size = 268435456; # 256MB — suppress "download buffer is full" warnings
        trusted-users = [
          "root"
          "@wheel"
        ];
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        # Host nix store substituter is conditionally loaded via
        # !include /etc/nix/host-store.conf (see nix.extraOptions below).
        # A systemd oneshot creates that file only when virtiofs is mounted.
        # Without this, local?root= on an empty dir aborts nix (no SQLite DB).
        require-sigs = false; # Host store paths are unsigned local builds
        trusted-substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };

      # Conditionally load host nix store substituter.
      # !include silently skips if the file doesn't exist (nix built-in).
      # The file is created by the konductor-host-nix-store systemd service
      # only when the virtiofs mount succeeds (deploy mode with host store).
      # Without virtiofs: file absent → no substituter → zero overhead.
      extraOptions = ''
        !include /etc/nix/host-store.conf
      '';

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

  # QCOW2 VM image using FAST builder (no cptofs bottleneck)
  #
  # Uses nixpkgs.lib.nixosSystem to evaluate konductorModule, then
  # accesses config.system.build.image which uses our custom
  # make-disk-image-fast.nix that copies files INSIDE the VM.
  #
  # No nixos-generators required - the image builder is defined
  # directly in konductorModule.system.build.image.
  inherit ((nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ konductorModule ];
  }).config.system.build) image;
}
