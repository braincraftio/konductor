# src/config/linters/eslint/default.nix
# Hermetic wrapper for eslint
#
# Config is maintained in native JS format (eslint.config.js) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native JS (flat config), copied to nix store
  configFile = pkgs.writeTextFile {
    name = "eslint-config";
    destination = "/eslint.config.js";
    text = builtins.readFile ./eslint.config.js;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "eslint";
    runtimeInputs = [ pkgs.nodePackages.eslint ];
    text = ''
      exec eslint --config "${configFile}/eslint.config.js" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.eslint;
  inherit configFile;

  meta = {
    description = "JavaScript linter";
    configurable = true;
  };
}
