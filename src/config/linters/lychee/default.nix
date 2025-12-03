# src/config/linters/lychee/default.nix
# Hermetic wrapper for lychee

{ pkgs, ... }:

let
  localConfigFile = ./lychee.toml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "lychee";
    runtimeInputs = [ pkgs.lychee ];
    text = ''
      exec lychee --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.lychee;
  inherit configFile;

  meta = {
    description = "Fast link checker";
    configurable = true;
  };
}
