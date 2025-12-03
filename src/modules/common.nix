# src/modules/common.nix
# Shared module options and package logic

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

  mkPackages = { cfg, pkgs, lib, versions }:
    let
      # Import packages with config wrappers
      configDir = ./.config/cli;
      config = import ../config { inherit pkgs configDir lib versions; };
      packages = import ../packages { inherit pkgs lib config versions; };
    in
    packages.base
    ++ packages.cli.packages
    ++ packages.linters.packages
    ++ packages.formatters.packages
    ++ lib.optionals cfg.enablePython [ pkgs.konductor.python pkgs.ruff pkgs.uv pkgs.poetry ]
    ++ lib.optionals cfg.enableGo [ pkgs.konductor.go pkgs.gopls pkgs.golangci-lint pkgs.delve pkgs.gofumpt ]
    ++ lib.optionals cfg.enableNode [ pkgs.konductor.nodejs pkgs.nodePackages.pnpm ]
    ++ lib.optionals cfg.enableRust [ pkgs.konductor.rustc ]
    ++ lib.optionals cfg.enableAI packages.ai.packages;

  # ===========================================================================
  # Environment Variables (imported from SSOT)
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases (imported from SSOT)
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
