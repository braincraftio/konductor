# src/config/formatters/biome/default.nix
# Hermetic wrapper for biome

{ pkgs, ... }:

let
  localConfigFile = ./biome.json;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "biome";
    runtimeInputs = [ pkgs.biome ];
    text = ''
      export BIOME_CONFIG_PATH="${configFile}"
      exec biome "$@"
    '';
  };

  unwrapped = pkgs.biome;
  inherit configFile;

  meta = {
    description = "JS/TS formatter and linter";
    configurable = true;
  };
}
