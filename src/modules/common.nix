# src/modules/common.nix
# Shared module options and package logic
#
# Pattern: mirrors src/devshells/default.nix and src/qcow2/default.nix
# catppuccinSources flows from flake inputs → module → mkPackages → config → packages

{ lib }:

let
  # Import canonical sources
  versions = import ../lib/versions.nix;
  langs = versions.languages;

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
    ++ lib.optionals cfg.enablePython packages.pythonPackages
    ++ lib.optionals cfg.enableGo packages.goPackages
    ++ lib.optionals cfg.enableNode packages.nodejsPackages
    ++ lib.optionals cfg.enableRust packages.rustPackages;

  # ===========================================================================
  # Environment Variables (imported from SSOT)
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases (imported from SSOT)
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
