# src/config/linters/ruff/default.nix
# Hermetic wrapper for ruff
#
# Config is maintained in native TOML format (ruff.toml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native TOML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "ruff-config";
    destination = "/ruff.toml";
    text = builtins.readFile ./ruff.toml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "ruff";
    runtimeInputs = [ pkgs.ruff ];
    text = ''
      exec ruff --config "${configFile}/ruff.toml" "$@"
    '';
  };

  unwrapped = pkgs.ruff;
  inherit configFile;

  meta = {
    description = "Python linter and formatter";
    configurable = true;
  };
}
