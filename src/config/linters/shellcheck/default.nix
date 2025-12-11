# src/config/linters/shellcheck/default.nix
# Hermetic wrapper for shellcheck
#
# Config is maintained in native format (.shellcheckrc) for easy contribution.
# The wrapper forces config via --rcfile flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native format, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "shellcheck-config";
    destination = "/.shellcheckrc";
    text = builtins.readFile ./.shellcheckrc;
  };
in
{
  # Wrapped version
  package = pkgs.writeShellApplication {
    name = "shellcheck";
    runtimeInputs = [ pkgs.shellcheck ];
    text = ''
      exec shellcheck --rcfile="${configFile}/.shellcheckrc" "$@"
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
