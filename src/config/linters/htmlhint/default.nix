# src/config/linters/htmlhint/default.nix
# Hermetic wrapper for htmlhint

{ pkgs, ... }:

let
  localConfigFile = ./.htmlhintrc;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "htmlhint";
    runtimeInputs = [ pkgs.htmlhint ];
    text = ''
      exec htmlhint --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.htmlhint;
  inherit configFile;

  meta = {
    description = "HTML linter";
    configurable = true;
  };
}
