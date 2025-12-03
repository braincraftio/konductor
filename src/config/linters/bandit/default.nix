# src/config/linters/bandit/default.nix
# Hermetic wrapper for bandit

{ pkgs, versions, ... }:

let
  localConfigFile = ./.bandit;
  configFile = "${localConfigFile}";
  # Use version-locked Python package
  pythonPkgs = pkgs."python${versions.languages.python.version}Packages";
in
{
  package = pkgs.writeShellApplication {
    name = "bandit";
    runtimeInputs = [ pythonPkgs.bandit ];
    text = ''
      exec bandit --configfile "${configFile}" "$@"
    '';
  };

  unwrapped = pythonPkgs.bandit;
  inherit configFile;

  meta = {
    description = "Python security linter";
    configurable = true;
  };
}
