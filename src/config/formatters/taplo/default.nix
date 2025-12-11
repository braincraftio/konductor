# src/config/formatters/taplo/default.nix
# Hermetic wrapper for taplo
#
# Config is maintained in native TOML format (taplo.toml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native TOML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "taplo-config";
    destination = "/taplo.toml";
    text = builtins.readFile ./taplo.toml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "taplo";
    runtimeInputs = [ pkgs.taplo ];
    text = ''
      exec taplo --config "${configFile}/taplo.toml" "$@"
    '';
  };

  unwrapped = pkgs.taplo;
  inherit configFile;

  meta = {
    description = "TOML formatter";
    configurable = true;
  };
}
