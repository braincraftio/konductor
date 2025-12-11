# src/config/linters/lychee/default.nix
# Hermetic wrapper for lychee
#
# Config is maintained in native TOML format (lychee.toml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native TOML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "lychee-config";
    destination = "/lychee.toml";
    text = builtins.readFile ./lychee.toml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "lychee";
    runtimeInputs = [ pkgs.lychee ];
    text = ''
      exec lychee --config "${configFile}/lychee.toml" "$@"
    '';
  };

  unwrapped = pkgs.lychee;
  inherit configFile;

  meta = {
    description = "Fast link checker";
    configurable = true;
  };
}
