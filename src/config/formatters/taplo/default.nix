# src/config/formatters/taplo/default.nix
# Hermetic wrapper for taplo

{ pkgs, ... }:

let
  localConfigFile = ./taplo.toml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "taplo";
    runtimeInputs = [ pkgs.taplo ];
    text = ''
      export TAPLO_CONFIG="${configFile}"
      exec taplo "$@"
    '';
  };

  unwrapped = pkgs.taplo;
  inherit configFile;

  meta = {
    description = "TOML formatter";
    configurable = true;
  };
}
