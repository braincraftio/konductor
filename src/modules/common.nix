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
    bashrcExtra = builtins.readFile ../config/shell/.bashrc_extra;
    initExtra = builtins.readFile ../config/shell/.bashrc;
    profileExtra = builtins.readFile ../config/shell/.bash_profile_extra;
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
