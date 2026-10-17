# src/config/linters/statix/default.nix
# Hermetic wrapper for statix
#
# statix reads statix.toml via -c, which only `check` and `fix` accept.
# The wrapper injects -c for those subcommands and passes others through.

{ pkgs }:

let
  configFile = pkgs.writeTextFile {
    name = "statix-config";
    destination = "/statix.toml";
    text = builtins.readFile ./statix.toml;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "statix";
    runtimeInputs = [ pkgs.statix ];
    text = ''
      if [ "$#" -eq 0 ]; then
        exec statix
      fi
      subcommand="$1"
      shift
      case "$subcommand" in
        check | fix)
          exec statix "$subcommand" --config "${configFile}/statix.toml" "$@"
          ;;
        *)
          exec statix "$subcommand" "$@"
          ;;
      esac
    '';
  };

  unwrapped = pkgs.statix;
  inherit configFile;

  meta = {
    description = "Nix linter";
    configurable = true;
  };
}
