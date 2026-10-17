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
    # --config is injected after the subcommands that read configuration;
    # every other subcommand (fmt, linters, version, help) passes through.
    text = ''
      if [ "$#" -eq 0 ]; then
        exec golangci-lint
      fi
      subcommand="$1"
      shift
      case "$subcommand" in
        run | fmt | linters | config)
          exec golangci-lint "$subcommand" --config "${configFile}/.golangci.yml" "$@"
          ;;
        *)
          exec golangci-lint "$subcommand" "$@"
          ;;
      esac
    '';
  };

  unwrapped = pkgs.golangci-lint;
  inherit configFile;

  meta = {
    description = "Go linter";
    configurable = true;
  };
}
