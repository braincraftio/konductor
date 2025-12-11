# src/config/linters/commitlint/default.nix
# Hermetic wrapper for commitlint
#
# Config is maintained in native CJS format (commitlint.config.cjs) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.

{ pkgs, ... }:

let
  # Config file - native CJS, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "commitlint-config";
    destination = "/commitlint.config.cjs";
    text = builtins.readFile ./commitlint.config.cjs;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "commitlint";
    runtimeInputs = [ pkgs.commitlint ];
    text = ''
      exec commitlint --config "${configFile}/commitlint.config.cjs" "$@"
    '';
  };

  unwrapped = pkgs.commitlint;
  inherit configFile;

  meta = {
    description = "Commit message linter";
    configurable = true;
  };
}
