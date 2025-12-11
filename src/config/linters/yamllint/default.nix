# src/config/linters/yamllint/default.nix
# Hermetic wrapper for yamllint
#
# Config is maintained in native YAML format (.yamllint.yaml) for easy contribution.
# The wrapper forces config via -c flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "yamllint-config";
    destination = "/.yamllint.yaml";
    text = builtins.readFile ./.yamllint.yaml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "yamllint";
    runtimeInputs = [ pkgs.yamllint ];
    text = ''
      exec yamllint -c "${configFile}/.yamllint.yaml" "$@"
    '';
  };

  unwrapped = pkgs.yamllint;
  inherit configFile;

  meta = {
    description = "YAML linter";
    configurable = true;
  };
}
