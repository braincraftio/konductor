# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier

{ pkgs, ... }:

let
  localConfigFile = ./.prettierrc.yaml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.nodePackages.prettier ];
    text = ''
      exec prettier --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.prettier;
  inherit configFile;

  meta = {
    description = "Code formatter";
    configurable = true;
  };
}
