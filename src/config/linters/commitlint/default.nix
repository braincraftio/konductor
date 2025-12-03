# src/config/linters/commitlint/default.nix
# Hermetic wrapper for commitlint

{ pkgs, ... }:

let
  localConfigFile = ./commitlint.config.cjs;
  configFile = "${localConfigFile}";
in
{
  package = pkgs.writeShellApplication {
    name = "commitlint";
    runtimeInputs = [ pkgs.commitlint ];
    text = ''
      exec commitlint --config "${configFile}" "$@"
    '';
  };

  unwrapped = pkgs.commitlint;
  inherit configFile;

  meta = {
    description = "Commit message linter";
    configurable = true;
  };
}
