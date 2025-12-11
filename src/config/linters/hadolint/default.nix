# src/config/linters/hadolint/default.nix
# Hermetic wrapper for hadolint
#
# Config is maintained in native YAML format (.hadolint.yaml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "hadolint-config";
    destination = "/.hadolint.yaml";
    text = builtins.readFile ./.hadolint.yaml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "hadolint";
    runtimeInputs = [ pkgs.hadolint ];
    text = ''
      exec hadolint --config "${configFile}/.hadolint.yaml" "$@"
    '';
  };

  unwrapped = pkgs.hadolint;
  inherit configFile;

  meta = {
    description = "Dockerfile linter";
    configurable = true;
  };
}
