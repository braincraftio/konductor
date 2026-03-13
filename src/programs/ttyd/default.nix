# src/programs/ttyd/default.nix
# ttyd web terminal with Catppuccin Frappé theme and embedded Nerd Fonts
#
# ttyd is a mature web terminal (xterm.js) for sharing terminals over HTTP/WebSocket.
# Theming via -t/--client-option flags (xterm.js ITerminalOptions).
#
# FONT EMBEDDING:
#   Fonts are embedded into ttyd binary at build time via src/overlays/ttyd.nix.
#   This works in airgapped environments - no CDN needed.
#   Uses JetBrains Mono Nerd Font Mono (single-width glyphs for terminal).
#
# Usage:
#   ttyd-konductor                       # Default: themed login shell on :7681
#   ttyd-konductor -p 8080               # Custom port
#   ttyd-konductor -w /home/user         # Custom working directory
#   ttyd-konductor -m 5                  # Max 5 concurrent clients
#   ttyd-konductor -b /terminal          # Base path for reverse proxy
#   ttyd-konductor -- tmux new -A -s dev # Custom command (use -- to separate)
#
# Konductor defaults (can be overridden):
#   --writable           Enable input (ttyd is readonly by default)
#   --cwd /workspace     Working directory
#   --port 7681          Standard web terminal port
#   --max-clients 10     Reasonable session limit
#   --interface 0.0.0.0  Bind all interfaces
#
# Reference:
#   https://github.com/tsl0922/ttyd
#   https://catppuccin.com/palette
#   https://github.com/ryanoasis/nerd-fonts

{ pkgs, ... }:

let
  # ===========================================================================
  # CATPPUCCIN FRAPPÉ THEME (xterm.js ITheme)
  # ===========================================================================
  # https://catppuccin.com/palette
  # Matches: tmux, neovim, opencode configs in this repo

  catppuccinFrappe = {
    # Base colors
    background = "#303446"; # base
    foreground = "#c6d0f5"; # text
    cursor = "#f2d5cf"; # rosewater
    cursorAccent = "#303446"; # base
    selectionBackground = "#626880"; # surface2
    selectionForeground = "#c6d0f5"; # text
    # ANSI Normal (0-7)
    black = "#51576d"; # surface1
    red = "#e78284"; # red
    green = "#a6d189"; # green
    yellow = "#e5c890"; # yellow
    blue = "#8caaee"; # blue
    magenta = "#ca9ee6"; # mauve
    cyan = "#81c8be"; # teal
    white = "#b5bfe2"; # subtext1
    # ANSI Bright (8-15)
    brightBlack = "#626880"; # surface2
    brightRed = "#e78284"; # red
    brightGreen = "#a6d189"; # green
    brightYellow = "#e5c890"; # yellow
    brightBlue = "#8caaee"; # blue
    brightMagenta = "#f4b8e4"; # pink
    brightCyan = "#99d1db"; # sky
    brightWhite = "#c6d0f5"; # text
  };

  # Convert theme to JSON string for ttyd -t option
  themeJson = builtins.toJSON catppuccinFrappe;

  # ===========================================================================
  # FONT CONFIGURATION
  # ===========================================================================
  # JetBrains Mono Nerd Font Mono - embedded into ttyd binary at build time
  # via src/overlays/ttyd.nix. Font-family must match @font-face declaration.
  # Fallback chain for systems without embedded fonts.

  fontFamily = "'JetBrainsMono Nerd Font Mono', 'JetBrains Mono', 'Fira Code', monospace";
  fontSize = "14";

  # ===========================================================================
  # KONDUCTOR DEFAULTS
  # ===========================================================================

  defaults = {
    port = "7681";
    interface = "0.0.0.0";
    cwd = "/workspace";
    maxClients = "10";
  };

  # ===========================================================================
  # WRAPPED TTYD
  # ===========================================================================
  # Wrapper that applies Catppuccin theme and Konductor-sensible defaults.
  # All ttyd options can be overridden by passing them before --.
  # Command to run should follow -- (or be the first non-flag argument).

  ttydKonductor = pkgs.writeShellScriptBin "ttyd-konductor" ''
    # ttyd with Catppuccin Frappé theme for Konductor
    # See: ttyd --help for all options
    #
    # Defaults applied (override with explicit flags):
    #   -W (writable), -w /workspace, -p 7681, -i 0.0.0.0, -m 10
    #   + Catppuccin Frappé theme via -t options

    set -euo pipefail

    # Theme configuration (xterm.js ITerminalOptions)
    THEME='${themeJson}'

    # Track which defaults have been overridden
    HAS_PORT=false
    HAS_INTERFACE=false
    HAS_CWD=false
    HAS_MAX_CLIENTS=false
    HAS_WRITABLE=false

    # Collect user-provided ttyd flags
    USER_FLAGS=()
    COMMAND=()
    SEEN_SEPARATOR=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      if $SEEN_SEPARATOR; then
        COMMAND+=("$1")
        shift
        continue
      fi

      case "$1" in
        --)
          SEEN_SEPARATOR=true
          shift
          ;;
        -p|--port)
          HAS_PORT=true
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        -i|--interface)
          HAS_INTERFACE=true
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        -w|--cwd)
          HAS_CWD=true
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        -m|--max-clients)
          HAS_MAX_CLIENTS=true
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        -W|--writable)
          HAS_WRITABLE=true
          USER_FLAGS+=("$1")
          shift
          ;;
        # WARNING: -I/--index replaces the ENTIRE HTML including all JS/CSS.
        # This will break the terminal unless you provide a complete HTML file
        # with all required xterm.js assets. Use with caution.
        -I|--index)
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        # Options that take a value (pass through)
        -c|--credential|-H|--auth-header|-u|--uid|-g|--gid|-s|--signal|-a|--url-arg|-t|--client-option|-T|--terminal-type|-b|--base-path|-P|--ping-interval|-C|--ssl-cert|-K|--ssl-key|-A|--ssl-ca|-U|--socket-owner|-d|--debug)
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        # Boolean flags (pass through)
        -O|--check-origin|-o|--once|-q|--exit-no-conn|-B|--browser|-6|--ipv6|-S|--ssl|-v|--version|-h|--help)
          USER_FLAGS+=("$1")
          shift
          ;;
        # First non-flag argument is start of command
        *)
          COMMAND+=("$1")
          shift
          # Collect remaining as command
          while [[ $# -gt 0 ]]; do
            COMMAND+=("$1")
            shift
          done
          ;;
      esac
    done

    # Build final argument list with defaults
    FINAL_ARGS=()

    # Apply defaults if not overridden
    if ! $HAS_WRITABLE; then
      FINAL_ARGS+=("--writable")
    fi
    if ! $HAS_PORT; then
      FINAL_ARGS+=("--port" "${defaults.port}")
    fi
    if ! $HAS_INTERFACE; then
      FINAL_ARGS+=("--interface" "${defaults.interface}")
    fi
    if ! $HAS_CWD; then
      FINAL_ARGS+=("--cwd" "${defaults.cwd}")
    fi
    if ! $HAS_MAX_CLIENTS; then
      FINAL_ARGS+=("--max-clients" "${defaults.maxClients}")
    fi

    # Add theme options (always applied, user can add more with -t)
    # Note: Fonts are embedded in ttyd binary via src/overlays/ttyd.nix
    FINAL_ARGS+=(
      -t "theme=$THEME"
      -t "fontSize=${fontSize}"
      -t "fontFamily=${fontFamily}"
      -t "cursorBlink=true"
      -t "scrollback=10000"
    )

    # Add user-provided flags
    FINAL_ARGS+=("''${USER_FLAGS[@]}")

    # Default command: login shell
    if [[ ''${#COMMAND[@]} -eq 0 ]]; then
      COMMAND=("''${SHELL:-/bin/bash}" "-l")
    fi

    # Execute
    exec ${pkgs.ttyd}/bin/ttyd "''${FINAL_ARGS[@]}" "''${COMMAND[@]}"
  '';

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Package list for inclusion in devshells
  packages = [
    ttydKonductor
    pkgs.ttyd # Raw ttyd for advanced use / debugging
  ];

  # Direct package reference
  wrapped = ttydKonductor;
  unwrapped = pkgs.ttyd;

  # Shell hook (empty - no setup needed)
  shellHook = "";

  # Environment variables (empty - all config via wrapper)
  env = { };

  # Theme export for other modules (NixOS service, etc.)
  theme = catppuccinFrappe;

  # Default configuration export (for documentation/NixOS module)
  inherit defaults;
}
