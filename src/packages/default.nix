# src/packages/default.nix
# Single Source of Truth for all package composition
#
# Architecture:
#   default  = core + network + system + cli + linters + formatters + ai
#   (Languages and IDE are composed at devshell level)
#
# This file exports:
#   - Individual category lists (core, network, system, cli, etc.)
#   - Individual language lists (pythonPackages, goPackages, etc.)
#   - IDE packages (idePackages)
#   - Composed 'default' set for base devshell/OCI/QCOW2

{ pkgs, lib, config ? null, versions }:

let
  # Import all package categories
  core = import ./core.nix { inherit pkgs; };
  network = import ./network.nix { inherit pkgs; };
  system = import ./system.nix { inherit pkgs lib; };
  languages = import ./languages.nix { inherit pkgs versions; };
  cli = import ./cli.nix { inherit pkgs; };
  linters = import ./linters.nix { inherit pkgs config; };
  formatters = import ./formatters.nix { inherit pkgs config; };
  ai = import ./ai.nix { inherit pkgs; };
  ide = import ./ide.nix { inherit pkgs; };

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

  # Default: The base for all devshells
  # This is what OCI and QCOW2 use
  default = corePackages ++ networkPackages ++ systemPackages ++ cliPackages ++ lintersPackages ++ formattersPackages ++ aiPackages;

  # ===========================================================================
  # LANGUAGE PACKAGES (added to default in language-specific shells)
  # ===========================================================================

  inherit (languages) pythonPackages goPackages nodejsPackages rustPackages;

  # ===========================================================================
  # IDE PACKAGES (added in dev and full shells)
  # ===========================================================================

  idePackages = ide.packages;

  # ===========================================================================
  # Individual Categories (for fine-grained control)
  # ===========================================================================
  inherit core network system languages cli linters formatters ai ide;

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
  env = (linters.env or { })
    // (formatters.env or { })
    // (ai.env or { });
}
