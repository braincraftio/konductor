# src/config/linters/bandit/default.nix
# Hermetic wrapper for bandit
#
# Config is maintained in native YAML format (.bandit) for easy contribution.
# The wrapper forces config via --configfile flag with no escape hatch.

{ pkgs, versions, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "bandit-config";
    destination = "/.bandit";
    text = builtins.readFile ./.bandit;
  };

  # Use version-locked Python package
  pythonPkgs = pkgs."python${versions.languages.python.version}Packages";
in
{
  package = pkgs.writeShellApplication {
    name = "bandit";
    runtimeInputs = [ pythonPkgs.bandit ];
    text = ''
      exec bandit --configfile "${configFile}/.bandit" "$@"
    '';
  };

  unwrapped = pythonPkgs.bandit;
  inherit configFile;

  meta = {
    description = "Python security linter";
    configurable = true;
  };
}
