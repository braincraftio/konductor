# src/config/linters/ruff/default.nix
# Hermetic wrapper for ruff

{ pkgs, ... }:

let
  localConfigFile = ./ruff.toml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "ruff";
    runtimeInputs = [ pkgs.ruff ];
    text = ''
      exec ruff --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.ruff;
  inherit configFile;

  meta = {
    description = "Python linter and formatter";
    configurable = true;
  };
}
