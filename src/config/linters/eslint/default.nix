# src/config/linters/eslint/default.nix
# Hermetic wrapper for eslint

{ pkgs, ... }:

let
  localConfigFile = ./eslint.config.js;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "eslint";
    runtimeInputs = [ pkgs.nodePackages.eslint ];
    text = ''
      exec eslint --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.eslint;
  inherit configFile;

  meta = {
    description = "JavaScript linter";
    configurable = true;
  };
}
