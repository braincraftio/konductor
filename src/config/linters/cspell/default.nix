# src/config/linters/cspell/default.nix
# Hermetic wrapper for cspell
#
# cspell.json and project-words.txt are copied together into one store
# directory so the dictionary's relative path resolves. The wrapper forces
# --config and pins the `lint` subcommand when the first argument is a path
# or option (bare `cspell <files>` is not a documented form in cspell 9).
# --no-config-search stops cspell merging cspell.json files found in parent
# directories of the checked files (a workspace above the repository), so the
# result depends only on this configuration.
#
# Seeding/maintaining project-words.txt: runme run lint:spell:words

{ pkgs }:

let
  configDir = pkgs.runCommand "cspell-config" { } ''
    mkdir -p $out
    cp ${./cspell.json} $out/cspell.json
    cp ${./project-words.txt} $out/project-words.txt
  '';
in
{
  package = pkgs.writeShellApplication {
    name = "cspell";
    runtimeInputs = [ pkgs.cspell ];
    text = ''
      case "''${1:-}" in
        lint | trace | check | suggestions | sug | dictionaries)
          subcommand="$1"
          shift
          exec cspell "$subcommand" --config "${configDir}/cspell.json" --no-config-search "$@"
          ;;
        init | link | help | -h | --help | -V | --version)
          exec cspell "$@"
          ;;
        *)
          exec cspell lint --config "${configDir}/cspell.json" --no-config-search "$@"
          ;;
      esac
    '';
  };

  unwrapped = pkgs.cspell;
  configFile = configDir;

  meta = {
    description = "Spell checker for code and docs";
    configurable = true;
  };
}
