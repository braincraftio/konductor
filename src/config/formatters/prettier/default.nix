# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier
#
# Config is maintained in native YAML format (.prettierrc.yaml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "prettier-config";
    destination = "/.prettierrc.yaml";
    text = builtins.readFile ./.prettierrc.yaml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.nodePackages.prettier ];
    text = ''
      exec prettier --config "${configFile}/.prettierrc.yaml" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.prettier;
  inherit configFile;

  meta = {
    description = "Code formatter";
    configurable = true;
  };
}
