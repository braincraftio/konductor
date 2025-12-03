# src/config/linters/golangci-lint/default.nix
# Hermetic wrapper for golangci-lint

{ pkgs, ... }:

let
  localConfigFile = ./.golangci.yml;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "golangci-lint";
    runtimeInputs = [ pkgs.golangci-lint ];
    text = ''
      exec golangci-lint run --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.golangci-lint;
  inherit configFile;

  meta = {
    description = "Go linter";
    configurable = true;
  };
}
