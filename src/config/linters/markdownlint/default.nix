# src/config/linters/markdownlint/default.nix
# Hermetic wrapper for markdownlint-cli2

{ pkgs, ... }:

let
  localConfigFile = ./.markdownlint-cli2.yaml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "markdownlint-cli2";
    runtimeInputs = [ pkgs.markdownlint-cli2 ];
    text = ''
      exec markdownlint-cli2 --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.markdownlint-cli2;
  inherit configFile;

  meta = {
    description = "Markdown linter";
    configurable = true;
  };
}
