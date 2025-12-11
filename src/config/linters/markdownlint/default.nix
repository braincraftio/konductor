# src/config/linters/markdownlint/default.nix
# Hermetic wrapper for markdownlint-cli2
#
# Config is maintained in native YAML format (.markdownlint-cli2.yaml) with
# rules defined inline under the 'config:' key. This avoids file reference
# issues when configs are in /nix/store.

{ pkgs, ... }:

let
  # Config file - native YAML, copied directly to nix store
  configFile = pkgs.writeTextFile {
    name = "markdownlint-cli2-config";
    destination = "/.markdownlint-cli2.yaml";
    text = builtins.readFile ./.markdownlint-cli2.yaml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "markdownlint-cli2";
    runtimeInputs = [ pkgs.markdownlint-cli2 ];
    text = ''
      exec markdownlint-cli2 --config "${configFile}/.markdownlint-cli2.yaml" "$@"
    '';
  };

  unwrapped = pkgs.markdownlint-cli2;
  inherit configFile;

  meta = {
    description = "Markdown linter";
    configurable = true;
  };
}
