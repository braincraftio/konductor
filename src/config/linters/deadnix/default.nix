# src/config/linters/deadnix/default.nix
# Hermetic wrapper for deadnix
#
# deadnix does not read .gitignore. Invoked without a target it recurses from
# `.`, descending into gitignored vendored trees (_sources/ holds full nixpkgs
# and rust-overlay checkouts).
#
# Argument contract (deterministic, no path guessing):
#   deadnix [OPTIONS]                → targets = tracked *.nix files (git ls-files)
#   deadnix [OPTIONS] -- [TARGETS]   → targets = exactly TARGETS
#   deadnix [OPTIONS] --             → no targets; exits 0
# Outside a git work tree, the no-`--` form is an error rather than a `.` scan.

{ pkgs }:

{
  package = pkgs.writeShellApplication {
    name = "deadnix";
    runtimeInputs = [
      pkgs.deadnix
      pkgs.git
    ];
    text = ''
      options=()
      targets=()
      explicit=0
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--" ]; then
          explicit=1
          shift
          targets=("$@")
          break
        fi
        options+=("$1")
        shift
      done

      if [ "$explicit" -eq 0 ]; then
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          echo "deadnix: not in a git work tree; pass targets after --" >&2
          exit 2
        fi
        mapfile -d "" targets < <(git ls-files -z --cached --others --exclude-standard -- '*.nix')
      fi

      if [ "''${#targets[@]}" -eq 0 ]; then
        exit 0
      fi

      exec deadnix "''${options[@]}" -- "''${targets[@]}"
    '';
  };

  unwrapped = pkgs.deadnix;
  configFile = null; # deadnix has no config file; scope is set by the wrapper

  meta = {
    description = "Dead Nix code detector scoped to git-tracked files";
    configurable = false;
  };
}
