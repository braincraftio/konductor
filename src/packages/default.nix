# src/packages/default.nix
# Single Source of Truth for all package composition
#
# Architecture:
#   default      = core + network + system + cli + linters + formatters + ai
#   fullPackages = default + IDE + all languages + container tooling
#
# This file exports:
#   - Individual category lists (core, network, system, cli, etc.)
#   - Individual language lists (pythonPackages, goPackages, etc.)
#   - IDE packages (idePackages)
#   - Container tooling (containerPackages)
#   - Full composite (fullPackages) — SSOT for full.nix, konductor.nix, modules
#   - Konductor self-hosting packages (konductor)
#   - Composed 'default' set for base devshell/OCI/QCOW2

{
  pkgs,
  lib,
  config ? null,
  versions,
}:

let
  # Import all package categories
  core = import ./core.nix { inherit pkgs; };
  network = import ./network.nix { inherit pkgs; };
  system = import ./system.nix { inherit pkgs lib; };
  languages = import ./languages.nix { inherit pkgs lib versions; };
  cli = import ./cli.nix {
    inherit pkgs config;
    inherit (languages) pulumiPkg;
  };
  linters = import ./linters.nix { inherit pkgs lib config; };
  formatters = import ./formatters.nix { inherit pkgs lib config; };
  ai = import ./ai.nix { inherit pkgs config; };
  ansible = import ./ansible { inherit pkgs lib; };
  ide = import ./ide.nix { inherit pkgs; };
  konductor = import ./konductor.nix { inherit pkgs; };
  tauri = import ./tauri.nix { inherit pkgs lib; };

  # Alias wrappers - executable scripts that provide hermetic "aliases"
  # These work with direnv (which can't export shell aliases)
  aliasWrappers = import ../lib/alias-wrappers.nix { inherit pkgs lib; };

in
rec {
  # ===========================================================================
  # BASE PACKAGES (default devshell, OCI container, QCOW2 VM)
  # ===========================================================================

  # Core Unix utilities
  corePackages = core.packages;

  # Network utilities
  networkPackages = network.packages;

  # System integration
  systemPackages = system.packages;

  # Modern CLI tools
  cliPackages = cli.packages;

  # Universal linters (language-agnostic)
  lintersPackages = linters.packages;

  # Universal formatters (language-agnostic)
  formattersPackages = formatters.packages;

  # AI tools
  aiPackages = ai.packages;

  # Ansible engine (ansible-core + httpx); lint tooling is the linters category
  ansiblePackages = ansible.packages;

  # Alias wrappers package (provides k, ll, la, etc. as executables)
  aliasWrappersPackage = [ aliasWrappers ];

  # Default: The base for all devshells
  # This is what OCI and QCOW2 use
  # aliasWrappers FIRST so they take priority in PATH
  default =
    aliasWrappersPackage
    ++ corePackages
    ++ networkPackages
    ++ systemPackages
    ++ cliPackages
    ++ lintersPackages
    ++ formattersPackages
    ++ aiPackages;

  # ===========================================================================
  # LANGUAGE PACKAGES (added to default in language-specific shells)
  # ===========================================================================

  inherit (languages)
    pythonEnv
    pythonPackages
    goPackages
    nodejsPackages
    rustPackages
    ;

  # ===========================================================================
  # IDE PACKAGES (added in dev and full shells)
  # ===========================================================================

  idePackages = ide.packages;

  # ===========================================================================
  # CONTAINER TOOLING
  # ===========================================================================
  # Linux: docker, docker-compose, docker-buildx from Nix
  # macOS: Docker Desktop provides these via Homebrew cask
  # skopeo: cross-platform, always from Nix
  containerPackages =
    lib.optionals pkgs.stdenv.isLinux (
      with pkgs;
      [
        docker_29
        docker-compose
        docker-buildx
      ]
    )
    ++ [ pkgs.skopeo ];

  # ===========================================================================
  # FULL PACKAGES (base + IDE + languages + container tooling)
  # ===========================================================================
  # Single composite for full.nix, konductor.nix, and modules/common.nix.
  # Excludes programs (neovim, tmux) and atuin — composed at the consumer level.
  fullPackages =
    default
    ++ idePackages
    ++ ansiblePackages
    ++ pythonPackages
    ++ goPackages
    ++ nodejsPackages
    ++ rustPackages
    ++ containerPackages;

  # ===========================================================================
  # KONDUCTOR SELF-HOSTING (added in konductor shell)
  # ===========================================================================

  # Full konductor module (packages, shellHook, env)
  inherit konductor;

  # ===========================================================================
  # TAURI BUILD DEPENDENCIES (for Tauri desktop applications)
  # ===========================================================================
  # Full tauri module (packages, shellHook, env, pkgConfigPath)
  inherit tauri;

  # ===========================================================================
  # Individual Categories (for fine-grained control)
  # ===========================================================================
  inherit
    core
    network
    system
    languages
    cli
    linters
    formatters
    ai
    ansible
    ide
    ;

  # ===========================================================================
  # Shell Hooks (aggregated from categories)
  # ===========================================================================
  shellHook = lib.concatStringsSep "\n" [
    (core.shellHook or "")
    (cli.shellHook or "")
    (linters.shellHook or "")
    (formatters.shellHook or "")
    (ai.shellHook or "")
  ];

  # ===========================================================================
  # Environment Variables (merged from categories, excluding languages)
  # ===========================================================================
  env = (cli.env or { }) // (linters.env or { }) // (formatters.env or { }) // (ai.env or { });
}
