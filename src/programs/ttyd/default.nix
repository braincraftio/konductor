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
#   --check-origin       Refuse cross-origin WebSocket (disable via env below)
#
# Config-driven options (systemd EnvironmentFile from konductor-init, or export):
#   KONDUCTOR_TTYD_CHECK_ORIGIN=true|false        default true
#   KONDUCTOR_TTYD_ENABLE_SIXEL=true|false        default false (inline images)
#   KONDUCTOR_TTYD_ENABLE_TRZSZ=true|false        default false (drag-drop transfer)
#   KONDUCTOR_TTYD_TRZSZ_DRAG_TIMEOUT=<ms>        default 3000
#   KONDUCTOR_TTYD_DISABLE_LEAVE_ALERT=true|false default false
#   KONDUCTOR_TTYD_TITLE=<string>                 unset (fixed browser title)
#   KONDUCTOR_TTYD_AUTH_HEADER=<header-name>      unset (-H; auth proxy identity —
#     enable ONLY behind an authenticating proxy that strips/sets this header,
#     ttyd returns 407 for requests without it)
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
  # SSOT: src/lib/theme.nix — do not add hex literals here.
  # Matches: tmux, neovim, opencode configs in this repo

  konductorTheme = import ../../lib/theme.nix;
  catppuccinFrappe = konductorTheme.xterm;

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
    HAS_CHECK_ORIGIN=false

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
        # check-origin: tracked so the wrapper default doesn't duplicate it
        -O|--check-origin)
          HAS_CHECK_ORIGIN=true
          USER_FLAGS+=("$1")
          shift
          ;;
        # Options that take a value (pass through)
        # NOTE: -a/--url-arg is NOT here — it is no_argument in ttyd's getopt
        # table (server.c); listing it as value-taking swallowed the next arg.
        -c|--credential|-H|--auth-header|-u|--uid|-g|--gid|-s|--signal|-t|--client-option|-T|--terminal-type|-b|--base-path|-P|--ping-interval|-f|--srv-buf-size|-C|--ssl-cert|-K|--ssl-key|-A|--ssl-ca|-U|--socket-owner|-d|--debug)
          USER_FLAGS+=("$1" "$2")
          shift 2
          ;;
        # Boolean flags (pass through)
        -a|--url-arg|-o|--once|-q|--exit-no-conn|-B|--browser|-6|--ipv6|-S|--ssl|-v|--version|-h|--help)
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

    # =========================================================================
    # Config-driven options (KONDUCTOR_TTYD_* environment)
    # =========================================================================
    # Set by konductor-init orchestrator via systemd EnvironmentFile
    # (/var/lib/konductor/services.toml), or exported manually.
    # Invalid values are hard errors (EX_USAGE) — no silent fallback.
    require_bool() {
      case "$2" in
        true|false) return 0 ;;
        *)
          echo "ttyd-konductor: invalid $1='$2' (valid: true, false)" >&2
          exit 64
          ;;
      esac
    }

    CHECK_ORIGIN="''${KONDUCTOR_TTYD_CHECK_ORIGIN:-true}"
    ENABLE_SIXEL="''${KONDUCTOR_TTYD_ENABLE_SIXEL:-false}"
    ENABLE_TRZSZ="''${KONDUCTOR_TTYD_ENABLE_TRZSZ:-false}"
    DISABLE_LEAVE_ALERT="''${KONDUCTOR_TTYD_DISABLE_LEAVE_ALERT:-false}"
    TRZSZ_DRAG_TIMEOUT="''${KONDUCTOR_TTYD_TRZSZ_DRAG_TIMEOUT:-3000}"
    require_bool KONDUCTOR_TTYD_CHECK_ORIGIN "$CHECK_ORIGIN"
    require_bool KONDUCTOR_TTYD_ENABLE_SIXEL "$ENABLE_SIXEL"
    require_bool KONDUCTOR_TTYD_ENABLE_TRZSZ "$ENABLE_TRZSZ"
    require_bool KONDUCTOR_TTYD_DISABLE_LEAVE_ALERT "$DISABLE_LEAVE_ALERT"
    case "$TRZSZ_DRAG_TIMEOUT" in
      ""|*[!0-9]*)
        echo "ttyd-konductor: invalid KONDUCTOR_TTYD_TRZSZ_DRAG_TIMEOUT='$TRZSZ_DRAG_TIMEOUT' (positive integer, milliseconds)" >&2
        exit 64
        ;;
    esac

    # check-origin: refuse WebSocket connections whose Origin != Host.
    # WebSockets are exempt from CORS — without this, any website a user
    # visits can open wss:// to this port from their browser.
    if ! $HAS_CHECK_ORIGIN && [ "$CHECK_ORIGIN" = "true" ]; then
      FINAL_ARGS+=("--check-origin")
    fi

    if [ "$ENABLE_SIXEL" = "true" ]; then
      FINAL_ARGS+=(-t "enableSixel=true")
    fi
    if [ "$ENABLE_TRZSZ" = "true" ]; then
      FINAL_ARGS+=(-t "enableTrzsz=true" -t "trzszDragInitTimeout=$TRZSZ_DRAG_TIMEOUT")
    fi
    if [ "$DISABLE_LEAVE_ALERT" = "true" ]; then
      FINAL_ARGS+=(-t "disableLeaveAlert=true")
    fi
    if [ -n "''${KONDUCTOR_TTYD_TITLE:-}" ]; then
      FINAL_ARGS+=(-t "titleFixed=''${KONDUCTOR_TTYD_TITLE}")
    fi
    if [ -n "''${KONDUCTOR_TTYD_AUTH_HEADER:-}" ]; then
      FINAL_ARGS+=(-H "''${KONDUCTOR_TTYD_AUTH_HEADER}")
    fi

    # Add user-provided flags
    # Client options merge last-wins server-side (json_object_object_add),
    # so user -t values override wrapper/env-provided ones.
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
