# src/config/linters/shellcheck/default.nix
# Hermetic wrapper for shellcheck

{ pkgs, ... }:

let
  localConfigFile = ./.shellcheckrc;
  configFile = "${localConfigFile}";
in
{
  # Wrapped version
  package = pkgs.writeShellApplication {
    name = "shellcheck";
    runtimeInputs = [ pkgs.shellcheck ];
    text = ''
      exec shellcheck --rcfile="${configFile}" "$@"
    '';
  };

  # Unwrapped version - for containers without config access
  unwrapped = pkgs.shellcheck;

  # Config file path - for validation and documentation
  inherit configFile;

  # Metadata
  meta = {
    description = "Shell script linter";
    configurable = true;
  };
}
