# src/config/formatters/biome/default.nix
# Hermetic wrapper for biome
#
# Config is maintained in native JSON format (biome.json) for easy contribution.
#
# biome only accepts --config-path AFTER a subcommand (biome 2.x rejects it in
# the global position: "flag --config-path is not valid in this context").
# The wrapper injects it after the subcommands that read configuration and
# passes every other invocation (--help, --version, explain, rage, ...) through.
#
# biome resolves vcs.useIgnoreFile relative to the config file's directory,
# which is the Nix store, so biome.json disables VCS integration. File scope
# comes from the caller (treefmt, lefthook staged files, explicit paths), which
# already applies the repository's .gitignore.
#
# files.includes negations are matched against absolute paths. biome.json
# therefore never excludes directory names that appear in a working tree's
# path prefix: `**/build/**` matches every file in the Nix build sandbox
# (/build/source) and `**/tmp/**` every checkout under /tmp, which made
# checks.treefmt skip all JS/TS/JSON silently (--no-errors-on-unmatched).

{ pkgs, ... }:

let
  # Config file - native JSON, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "biome-config";
    destination = "/biome.json";
    text = builtins.readFile ./biome.json;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "biome";
    runtimeInputs = [ pkgs.biome ];
    text = ''
      if [ "$#" -eq 0 ]; then
        exec biome
      fi
      subcommand="$1"
      shift
      case "$subcommand" in
        check | lint | format | ci | search | migrate)
          exec biome "$subcommand" --config-path "${configFile}/biome.json" "$@"
          ;;
        *)
          exec biome "$subcommand" "$@"
          ;;
      esac
    '';
  };

  unwrapped = pkgs.biome;
  inherit configFile;

  meta = {
    description = "JS/TS/JSON formatter and linter";
    configurable = true;
  };
}
