# src/config/tree/default.nix
# Hermetic wrapper for eza --tree with optimized defaults
#
# Leverages eza's --git-ignore and -I flags for filtering.
# Default depth 6, colorized, directories first, icons.
#
# Usage:
#   tree                    # Current dir, depth 6, gitignore + treeignore filtering
#   tree -L 2               # Override depth
#   tree src/               # Specific path
#   tree -a                 # Show hidden files (eza native, passed through)
#   tree --raw              # Escape hatch: raw eza --tree, no Konductor defaults
#   tree --raw -a -L 10     # Raw mode with custom eza flags
#
# Filtering layers:
#   1. --git-ignore respects project .gitignore
#   2. -I adds .treeignore patterns (lock files, IDE configs, etc.)

{ pkgs, ... }:

let
  # Read and parse .treeignore patterns
  ignorePatterns = builtins.readFile ./.treeignore;

  # Filter comments and empty lines, convert to pipe-separated string
  patternLines = builtins.filter
    (line:
      line != "" &&
      !(pkgs.lib.hasPrefix "#" line) &&
      !(pkgs.lib.hasPrefix " " line)
    )
    (pkgs.lib.splitString "\n" ignorePatterns);

  # Join with | for eza -I flag
  # - Remove trailing slashes for eza compatibility
  # - Prefix with **/ to match anywhere in tree (eza globs are anchored)
  excludePattern = builtins.concatStringsSep "|" (
    map
      (p:
        let clean = pkgs.lib.removeSuffix "/" p;
        in if pkgs.lib.hasPrefix "*" clean then clean else "**/${clean}"
      )
      patternLines
  );

  # Treeignore file in nix store for reference
  treeignoreFile = pkgs.writeText "treeignore" ignorePatterns;
in
{
  # Wrapped version with optimized defaults
  package = pkgs.writeShellApplication {
    name = "tree";
    runtimeInputs = [ pkgs.eza ];
    text = ''
      # Parse arguments to detect user overrides
      DEPTH_SET=false
      RAW_MODE=false
      ARGS=()
      EXTRA_EZA_ARGS=()

      # Track flags to avoid duplicates (braincraft wrapper may pass same flag twice)
      HAS_ALL=false
      HAS_CLASSIFY=false
      HAS_DIRS_ONLY=false
      HAS_REVERSE=false

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
          --raw|--no-filter)
            # Escape hatch: disable all Konductor defaults, raw eza passthrough
            RAW_MODE=true
            ;;
          # GNU tree flag translation to eza equivalents (with deduplication)
          -C|--color)
            # GNU tree colorize -> eza --color=always (already default)
            ;;
          -n)
            # GNU tree no color -> eza --color=never
            EXTRA_EZA_ARGS+=(--color=never)
            ;;
          -F)
            # GNU tree classify -> eza --classify=always
            if [[ "$HAS_CLASSIFY" == false ]]; then
              EXTRA_EZA_ARGS+=(--classify=always)
              HAS_CLASSIFY=true
            fi
            ;;
          -a|--all)
            # GNU tree show all -> eza --all
            if [[ "$HAS_ALL" == false ]]; then
              EXTRA_EZA_ARGS+=(--all)
              HAS_ALL=true
            fi
            ;;
          -d)
            # GNU tree directories only -> eza --only-dirs
            if [[ "$HAS_DIRS_ONLY" == false ]]; then
              EXTRA_EZA_ARGS+=(--only-dirs)
              HAS_DIRS_ONLY=true
            fi
            ;;
          -r)
            # GNU tree reverse sort -> eza --reverse
            if [[ "$HAS_REVERSE" == false ]]; then
              EXTRA_EZA_ARGS+=(--reverse)
              HAS_REVERSE=true
            fi
            ;;
          -f)
            # GNU tree full path -> eza --absolute
            EXTRA_EZA_ARGS+=(--absolute)
            ;;
          -s)
            # GNU tree show size -> eza --long (shows size in long format)
            EXTRA_EZA_ARGS+=(--long --no-permissions --no-user --no-time)
            ;;
          -D)
            # GNU tree show date -> eza --long with time
            EXTRA_EZA_ARGS+=(--long --no-permissions --no-user --no-filesize)
            ;;
          --dirsfirst|--group-directories-first)
            # GNU tree dirs first -> eza --group-directories-first (already default)
            ;;
          --prune|--noreport)
            # GNU tree flags not supported by eza, ignore
            ;;
          -I)
            # GNU tree ignore pattern -> eza --ignore-glob
            if [[ -n "''${2:-}" ]]; then
              EXTRA_EZA_ARGS+=(--ignore-glob="$2")
              shift
            fi
            ;;
          -P)
            # GNU tree pattern match - not directly supported, skip
            if [[ -n "''${2:-}" ]]; then
              shift
            fi
            ;;
          -o)
            # GNU tree output file - skip flag and argument
            if [[ -n "''${2:-}" ]]; then
              shift
            fi
            ;;
          *)
            ARGS+=("$1")
            ;;
        esac
        shift
      done

      if [[ "$RAW_MODE" == true ]]; then
        # Raw mode: just eza --tree with user args, no Konductor defaults
        exec eza --tree "''${EXTRA_EZA_ARGS[@]}" "''${ARGS[@]}"
      fi

      # Build command with Konductor defaults
      CMD=(eza --tree)

      # Visual defaults: color, icons, dirs first
      CMD+=(--color=always --icons=always --group-directories-first)

      # Default depth 6 unless user specified -L
      if [[ "$DEPTH_SET" == false ]]; then
        CMD+=(-L 6)
      fi

      # Filtering: gitignore + treeignore
      CMD+=(--git-ignore)
      CMD+=(-I '${excludePattern}')

      exec "''${CMD[@]}" "''${EXTRA_EZA_ARGS[@]}" "''${ARGS[@]}"
    '';
  };

  # Unwrapped eza for direct access
  unwrapped = pkgs.eza;

  # Treeignore file path - for reference/copying to projects
  inherit treeignoreFile;

  # The exclude pattern string - for debugging
  inherit excludePattern;

  # Metadata
  meta = {
    description = "eza --tree with gitignore-aware filtering and optimized defaults";
    configurable = true;
    defaults = {
      depth = 6;
      colorize = true;
      icons = true;
      directoriesFirst = true;
      useGitignore = true;
    };
  };
}
