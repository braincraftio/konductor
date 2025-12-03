# src/config/linters/yamllint/default.nix
# Hermetic wrapper for yamllint

{ pkgs, ... }:

let
  localConfigFile = ./.yamllint.yaml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "yamllint";
    runtimeInputs = [ pkgs.yamllint ];
    text = ''
      exec yamllint -c "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.yamllint;
  inherit configFile;

  meta = {
    description = "YAML linter";
    configurable = true;
  };
}
