# src/config/linters/hadolint/default.nix
# Hermetic wrapper for hadolint

{ pkgs, ... }:

let
  localConfigFile = ./.hadolint.yaml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "hadolint";
    runtimeInputs = [ pkgs.hadolint ];
    text = ''
      exec hadolint --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.hadolint;
  inherit configFile;

  meta = {
    description = "Dockerfile linter";
    configurable = true;
  };
}
