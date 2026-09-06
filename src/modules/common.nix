# src/modules/common.nix
# Shared module options and package logic
#
# Pattern: mirrors src/devshells/default.nix and src/qcow2/default.nix
# catppuccinSources flows from flake inputs → module → mkPackages → config → packages
#
# Exports:
#   mkOptions    - NixOS/HM/darwin option definitions
#   mkPackages   - Full devshell packages (SSOT: packages/default.nix fullPackages)
#   mkPrograms   - IDE program packages: neovim, tmux, ttyd (for home.packages)
#   mkHomeFiles  - Config files for home.file (bashrc, starship, atuin, etc.)
#   mkFullEnv    - All environment variables including tool config paths
#   mkEnv        - Base environment variables (EDITOR, PAGER, etc.)
#   mkAliases    - Shell aliases

{ lib }:

{
  # ===========================================================================
  # Shared Option Definitions
  # ===========================================================================

  mkOptions = {
    enable = lib.mkEnableOption "Konductor development environment";
  };

  # ===========================================================================
  # Package Builder (called by platform modules)
  # ===========================================================================
  # Mirrors the package composition in src/devshells/default.nix:
  #   catppuccinSources → config → packages → composed list

  mkPackages =
    {
      pkgs,
      lib,
      versions,
      catppuccinSources,
    }:
    let
      # Config provides wrapped linters/formatters with hermetic configuration
      # catppuccinSources enables k9s Catppuccin theme (same as devshells + qcow2)
      config = import ../config {
        inherit
          pkgs
          lib
          versions
          catppuccinSources
          ;
      };

      # Single source of truth for package composition
      packages = import ../packages {
        inherit
          pkgs
          lib
          config
          versions
          ;
      };
    in
    # fullPackages = base + IDE + all languages + container tooling (SSOT with full.nix)
    packages.fullPackages
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux packages.konductor.packages
    ++ [ pkgs.nerd-fonts.jetbrains-mono ];

  # ===========================================================================
  # Program Packages (IDE tools: neovim, tmux, ttyd)
  # ===========================================================================
  # Same composition as src/devshells/konductor.nix nativeBuildInputs
  # Requires programs and packages from the caller (needs flake inputs for nixvim)

  mkPrograms =
    { programs, packages }:
    programs.neovim.packages
    ++ programs.tmux.packages
    ++ programs.ttyd.packages
    ++ packages.idePackages;

  # ===========================================================================
  # Home Files (config files not managed by programs.bash)
  # ===========================================================================

  mkHomeFiles =
    { config }:
    {
      ".config/starship.toml".text = config.shell.starship.configContent;
      ".config/atuin/config.toml" = {
        text = config.shell.atuin.configContent;
        force = true;
      };
    };

  # ===========================================================================
  # programs.bash configuration
  # ===========================================================================
  # home-manager programs.bash generates .bashrc, .bash_profile, .profile.
  # targets.genericLinux sources hm-session-vars.sh in .bashrc for non-login shells.

  mkBashConfig = {
    enable = true;

    # Non-interactive content before the interactive guard
    bashrcExtra = ''
      # Source *.sh from ~/.bashrc.d/ for host-specific configuration
      if [ -d "$HOME/.bashrc.d" ] && [[ $- == *i* ]]; then
        for f in "$HOME/.bashrc.d"/*.sh; do
          [ -f "$f" ] && source "$f"
        done
      fi

      # Clear aliases that conflict with wrapper scripts in PATH
      unalias cat 2>/dev/null || true
      unalias grep 2>/dev/null || true
    '';

    # Interactive content shared with devshells via src/config/shell/.bashrc
    initExtra = builtins.readFile ../config/shell/.bashrc;

    # Login shell content for .profile
    profileExtra = ''
      # Nix PATH guard to prevent nix-daemon.sh from re-prepending nix paths
      if [[ ":$PATH:" == *"/.nix-profile/bin:"* ]]; then
        __ETC_PROFILE_NIX_SOURCED=1
      fi

      if [ -f /etc/profile ] && [ "$(uname)" != "Darwin" ]; then
        source /etc/profile
      fi

      export __ETC_PROFILE_NIX_SOURCED=1

      # Deduplicate XDG_DATA_DIRS
      if [ -n "''${XDG_DATA_DIRS:-}" ]; then
        XDG_DATA_DIRS="$(printf '%s' "$XDG_DATA_DIRS" | awk -v RS=: -v ORS=: '!seen[$0]++')"
        XDG_DATA_DIRS="''${XDG_DATA_DIRS%:}"
        export XDG_DATA_DIRS
      fi
    '';
  };

  # ===========================================================================
  # programs.readline replaces home.file .inputrc
  # ===========================================================================

  mkReadlineConfig = {
    variables = {
      enable-keypad = true;
      input-meta = true;
      output-meta = true;
      convert-meta = false;
      completion-ignore-case = true;
      show-all-if-ambiguous = true;
      colored-stats = true;
    };
    bindings = {
      "\\e[A" = "previous-history";
      "\\e[B" = "next-history";
      "\\e[C" = "forward-char";
      "\\e[D" = "backward-char";
      "\\e[H" = "beginning-of-line";
      "\\e[F" = "end-of-line";
      "\\e[3~" = "delete-char";
    };
  };

  # ===========================================================================
  # Full Environment Variables
  # ===========================================================================
  # Merges env.nix with tool-specific config paths.
  # BASH_ENV excluded to prevent infinite recursion when tools like starship
  # spawn non-interactive bash subprocesses.

  mkFullEnv =
    {
      config,
      sslCertFile ? "/etc/ssl/certs/ca-certificates.crt",
    }:
    import ../lib/env.nix
    // (builtins.removeAttrs config.shell.bash.env [ "BASH_ENV" ])
    // config.shell.atuin.env
    // {
      KONDUCTOR = "true";
      SSL_CERT_FILE = sslCertFile;
      NIX_SSL_CERT_FILE = sslCertFile;
    };

  # ===========================================================================
  # Base Environment Variables
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
