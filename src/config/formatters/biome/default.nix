# src/config/formatters/biome/default.nix
# Hermetic wrapper for biome
#
# Config is maintained in native JSON format (biome.json) for easy contribution.
# The wrapper forces config via --config-path flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native JSON, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "biome-config";
    destination = "/biome.json";
    text = builtins.readFile ./biome.json;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "biome";
    runtimeInputs = [ pkgs.biome ];
    text = ''
      exec biome --config-path "${configFile}/biome.json" "$@"
    '';
  };

  unwrapped = pkgs.biome;
  inherit configFile;

  meta = {
    description = "JS/TS formatter and linter";
    configurable = true;
  };
}
