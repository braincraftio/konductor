# src/config/linters/golangci-lint/default.nix
# Hermetic wrapper for golangci-lint
#
# Config is maintained in native YAML format (.golangci.yml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "golangci-lint-config";
    destination = "/.golangci.yml";
    text = builtins.readFile ./.golangci.yml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "golangci-lint";
    runtimeInputs = [ pkgs.golangci-lint ];
    text = ''
      exec golangci-lint run --config "${configFile}/.golangci.yml" "$@"
    '';
  };

  unwrapped = pkgs.golangci-lint;
  inherit configFile;

  meta = {
    description = "Go linter";
    configurable = true;
  };
}
