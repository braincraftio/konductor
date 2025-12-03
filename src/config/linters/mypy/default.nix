# src/config/linters/mypy/default.nix
# Hermetic wrapper for mypy

{ pkgs, ... }:

let
  localConfigFile = ./mypy.ini;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "mypy";
    runtimeInputs = [ pkgs.mypy ];
    text = ''
      exec mypy --config-file "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.mypy;
  inherit configFile;

  meta = {
    description = "Python type checker";
    configurable = true;
  };
}
