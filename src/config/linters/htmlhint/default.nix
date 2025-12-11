# src/config/linters/htmlhint/default.nix
# Hermetic wrapper for htmlhint
#
# Config is maintained in native format (.htmlhintrc) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native format, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "htmlhint-config";
    destination = "/.htmlhintrc";
    text = builtins.readFile ./.htmlhintrc;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "htmlhint";
    runtimeInputs = [ pkgs.htmlhint ];
    text = ''
      exec htmlhint --config "${configFile}/.htmlhintrc" "$@"
    '';
  };

  unwrapped = pkgs.htmlhint;
  inherit configFile;

  meta = {
    description = "HTML linter";
    configurable = true;
  };
}
