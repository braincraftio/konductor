# src/config/linters/mypy/default.nix
# Hermetic wrapper for mypy
#
# Config is maintained in native INI format (mypy.ini) for easy contribution.
# The wrapper forces config via --config-file flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native INI, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "mypy-config";
    destination = "/mypy.ini";
    text = builtins.readFile ./mypy.ini;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "mypy";
    runtimeInputs = [ pkgs.mypy ];
    text = ''
      exec mypy --config-file "${configFile}/mypy.ini" "$@"
    '';
  };

  unwrapped = pkgs.mypy;
  inherit configFile;

  meta = {
    description = "Python type checker";
    configurable = true;
  };
}
