# src/config/tree/default.nix
# Hermetic wrapper for tree with optimized defaults
#
# Leverages tree's native --gitignore and --gitfile flags for filtering.
# Default depth 6, colorized, directories first, pruned empty dirs.
#
# Usage:
#   tree                    # Current dir, depth 6, gitignore + treeignore
#   tree -L 2               # Override depth
#   tree src/               # Specific path
#   tree --no-gitignore     # Disable .gitignore filtering (keeps treeignore)
#   tree --no-filter        # Disable all filtering
#
# Filtering layers:
#   1. --gitignore respects project .gitignore (node_modules, build/, etc.)
#   2. --gitfile adds .treeignore patterns (lock files, IDE configs, etc.)

{ pkgs, ... }:

let
  # Treeignore file in nix store for hermeticity
  treeignoreFile = pkgs.writeText "treeignore" (builtins.readFile ./.treeignore);
in
{
  # Wrapped version with optimized defaults
  package = pkgs.writeShellApplication {
    name = "tree";
    runtimeInputs = [ pkgs.tree ];
    text = ''
      # Parse arguments to detect user overrides
      DEPTH_SET=false
      NO_FILTER=false
      NO_GITIGNORE=false
      ARGS=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -L)
            DEPTH_SET=true
            ARGS+=("$1")
            if [[ -n "''${2:-}" && "''${2:-}" =~ ^[0-9]+$ ]]; then
              ARGS+=("$2")
              shift
            fi
            ;;
          --no-filter|--no-exclude|--all)
            NO_FILTER=true
            ;;
          --no-gitignore)
            NO_GITIGNORE=true
            ;;
          *)
            ARGS+=("$1")
            ;;
        esac
        shift
      done

      # Build command
      CMD=(command tree)

      # Visual defaults: color, type indicators, dirs first, prune empty
      CMD+=(-C -F --dirsfirst --prune)

      # Default depth 6 unless user specified -L
      if [[ "$DEPTH_SET" == false ]]; then
        CMD+=(-L 6)
      fi

      # Filtering: gitignore + treeignore unless disabled
      if [[ "$NO_FILTER" == false ]]; then
        if [[ "$NO_GITIGNORE" == false ]]; then
          CMD+=(--gitignore)
        fi
        CMD+=(--gitfile="${treeignoreFile}")
      fi

      exec "''${CMD[@]}" "''${ARGS[@]}"
    '';
  };

  # Unwrapped version - standard tree
  unwrapped = pkgs.tree;

  # Treeignore file path - for reference/copying to projects
  inherit treeignoreFile;

  # Metadata
  meta = {
    description = "Tree with gitignore-aware filtering and optimized defaults";
    configurable = true;
    defaults = {
      depth = 6;
      colorize = true;
      directoriesFirst = true;
      pruneEmpty = true;
      useGitignore = true;
    };
  };
}
