# src/config/linters/stylelint/default.nix
# Hermetic wrapper for stylelint
#
# Config is maintained in native JSON format (.stylelintrc.json) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native JSON, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "stylelint-config";
    destination = "/.stylelintrc.json";
    text = builtins.readFile ./.stylelintrc.json;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "stylelint";
    runtimeInputs = [ pkgs.nodePackages.stylelint ];
    text = ''
      exec stylelint --config "${configFile}/.stylelintrc.json" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.stylelint;
  inherit configFile;

  meta = {
    description = "CSS/SCSS linter";
    configurable = true;
  };
}
