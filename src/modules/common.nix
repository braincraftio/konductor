# src/modules/common.nix
# Shared module options and package logic
#
# Pattern: mirrors src/devshells/default.nix and src/qcow2/default.nix
# catppuccinSources flows from flake inputs → module → mkPackages → config → packages
#
# Exports:
#   mkOptions    - NixOS/HM/darwin option definitions
#   mkPackages   - Base + language packages (for environment.systemPackages / home.packages)
#   mkPrograms   - IDE program packages: neovim, tmux, ttyd (for home.packages)
#   mkHomeFiles  - Config files for home.file (bashrc, starship, atuin, etc.)
#   mkFullEnv    - All environment variables including tool config paths
#   mkEnv        - Base environment variables (EDITOR, PAGER, etc.)
#   mkAliases    - Shell aliases

{ lib }:

let
  # Import canonical sources
  versions = import ../lib/versions.nix;
  langs = versions.languages;
  shellContent = import ../lib/shell-content.nix { inherit lib; };

in
{
  # ===========================================================================
  # Shared Option Definitions
  # ===========================================================================

  mkOptions = {
    enable = lib.mkEnableOption "Konductor development environment";

    enablePython = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Python ${langs.python.display} toolchain";
    };

    enableGo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Go ${langs.go.display} toolchain";
    };

    enableNode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Node.js ${langs.node.display} toolchain";
    };

    enableRust = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Rust ${langs.rust.display} toolchain";
    };

    enableDevOps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable DevOps/Cloud tooling";
    };

    enableAI = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable AI coding assistants";
    };
  };

  # ===========================================================================
  # Package Builder (called by platform modules)
  # ===========================================================================
  # Mirrors the package composition in src/devshells/default.nix:
  #   catppuccinSources → config → packages → composed list

  mkPackages = { cfg, pkgs, lib, versions, catppuccinSources }:
    let
      # Config provides wrapped linters/formatters with hermetic configuration
      # catppuccinSources enables k9s Catppuccin theme (same as devshells + qcow2)
      config = import ../config { inherit pkgs lib versions catppuccinSources; };

      # Single source of truth for package composition
      packages = import ../packages { inherit pkgs lib config versions; };
    in
    packages.default
    ++ [ pkgs.nerd-fonts.jetbrains-mono ]
    ++ lib.optionals cfg.enablePython packages.pythonPackages
    ++ lib.optionals cfg.enableGo packages.goPackages
    ++ lib.optionals cfg.enableNode packages.nodejsPackages
    ++ lib.optionals cfg.enableRust packages.rustPackages;

  # ===========================================================================
  # Program Packages (IDE tools: neovim, tmux, ttyd)
  # ===========================================================================
  # Same composition as src/devshells/konductor.nix nativeBuildInputs
  # Requires programs and packages from the caller (needs flake inputs for nixvim)

  mkPrograms = { programs, packages }:
    programs.neovim.packages
    ++ programs.tmux.packages
    ++ programs.ttyd.packages
    ++ packages.idePackages;

  # ===========================================================================
  # Home Files (config files managed by home.file)
  # ===========================================================================
  # Same pattern as src/qcow2/default.nix homeManagerUserConfig (line 439-455)

  mkHomeFiles = { config }:
    {
      ".bashrc".text = config.shell.bash.bashrcContent;
      ".bash_profile".text = shellContent.bashProfileContent;
      ".inputrc".text = shellContent.inputrcContent;
      ".config/starship.toml".text = config.shell.starship.configContent;
      ".config/atuin/config.toml" = {
        text = config.shell.atuin.configContent;
        force = true;
      };
    };

  # ===========================================================================
  # Full Environment Variables (base + tool config paths)
  # ===========================================================================
  # Merges env.nix (EDITOR, PAGER, etc.) with tool-specific config paths
  # (KONDUCTOR_BASHRC, ATUIN_CONFIG_DIR, KONDUCTOR_PREEXEC_PATH, etc.)
  #
  # BASH_ENV is excluded: it points to the konductor bashrc which causes
  # infinite recursion when tools like starship spawn non-interactive bash
  # subprocesses (BASH_ENV → bashrc → starship init → bash → BASH_ENV → ...).
  # QCOW2 sets BASH_ENV="/etc/set-environment" (NixOS-specific) instead.
  # For home-manager, .bash_profile → .bashrc handles interactive shells.

  mkFullEnv = { config }:
    import ../lib/env.nix
    // (builtins.removeAttrs config.shell.bash.env [ "BASH_ENV" ])
    // config.shell.atuin.env
    // { KONDUCTOR = "true"; };

  # ===========================================================================
  # Base Environment Variables (imported from SSOT)
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases (imported from SSOT)
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
