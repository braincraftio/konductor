# src/config/shell/starship.nix
# Starship prompt wrapper - slurps starship.toml
#
# The wrapper forces config via STARSHIP_CONFIG env var.
# Config is SSOT in starship.toml alongside this file.

{ pkgs }:

let
  # Slurp the config file
  configContent = builtins.readFile ./starship.toml;

  # Config file - written to nix store
  configFile = pkgs.writeTextFile {
    name = "konductor-starship-config";
    destination = "/starship.toml";
    text = configContent;
  };

in
{
  # Wrapped starship that forces hermetic config
  package = pkgs.writeShellApplication {
    name = "starship";
    runtimeInputs = [ pkgs.starship ];
    text = ''
      export STARSHIP_CONFIG="${configFile}/starship.toml"
      exec starship "$@"
    '';
  };

  unwrapped = pkgs.starship;

  # Config file and content (for consumers like qcow2, oci)
  inherit configFile;
  inherit configContent;

  # Metadata
  meta = {
    description = "Starship prompt with Konductor theme";
    configurable = true;
  };
}
