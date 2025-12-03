# src/config/linters/stylelint/default.nix
# Hermetic wrapper for stylelint

{ pkgs, ... }:

let
  localConfigFile = ./.stylelintrc.json;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "stylelint";
    runtimeInputs = [ pkgs.nodePackages.stylelint ];
    text = ''
      exec stylelint --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.stylelint;
  inherit configFile;

  meta = {
    description = "CSS/SCSS linter";
    configurable = true;
  };
}
