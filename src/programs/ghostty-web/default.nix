# src/programs/ghostty-web/default.nix
# Ghostty Web Terminal - PTY server package for Konductor
#
# Provides browser-accessible terminal via HTTP + WebSocket.
# Designed for KubeVirt VM deployment behind Envoy Gateway (OIDC).
#
# FONT EMBEDDING:
#   Fonts are embedded into index.html at build time (same pattern as ttyd).
#   Uses JetBrains Mono Nerd Font Mono from nixpkgs nerd-fonts.
#   This fixes the "blocky" rendering issue by ensuring fonts are available
#   BEFORE the terminal measures character metrics.
#
# ESM Module Resolution:
# - Node.js ESM ignores NODE_PATH environment variable
# - Solution: Place server.js and node_modules as siblings
# - Use makeWrapper --chdir to set CWD to application directory
#
# Dependencies:
# - node-pty (microsoft/node-pty v1.1.0) - PTY management, built from source
# - ws - WebSocket server
# - ghostty-web - WASM terminal frontend (fetched from npm)

{ pkgs, lib, ... }:

let
  # ===========================================================================
  # CATPPUCCIN FRAPPE THEME (exported for NixOS module)
  # ===========================================================================
  # https://catppuccin.com/palette
  # Matches: tmux, neovim, opencode, ttyd configs in this repo

  catppuccinFrappe = {
    # Base colors
    background = "#303446";   # base
    foreground = "#c6d0f5";   # text
    cursor = "#f2d5cf";       # rosewater
    cursorAccent = "#303446"; # base
    selectionBackground = "rgba(131, 139, 167, 0.3)";  # overlay1 @ 30%
    selectionForeground = "#c6d0f5";  # text
    # ANSI Normal (0-7)
    black = "#51576d";        # surface1
    red = "#e78284";          # red
    green = "#a6d189";        # green
    yellow = "#e5c890";       # yellow
    blue = "#8caaee";         # blue
    magenta = "#ca9ee6";      # mauve
    cyan = "#81c8be";         # teal
    white = "#b5bfe2";        # subtext1
    # ANSI Bright (8-15)
    brightBlack = "#626880";  # surface2
    brightRed = "#e78284";    # red
    brightGreen = "#a6d189";  # green
    brightYellow = "#e5c890"; # yellow
    brightBlue = "#8caaee";   # blue
    brightMagenta = "#f4b8e4"; # pink
    brightCyan = "#99d1db";   # sky
    brightWhite = "#c6d0f5";  # text
  };

  # ===========================================================================
  # FONT CONFIGURATION
  # ===========================================================================
  # JetBrains Mono Nerd Font Mono - embedded at build time
  # Font-family must match @font-face declaration in embedded CSS

  fontFamily = "'JetBrainsMono Nerd Font Mono', 'JetBrains Mono', monospace";
  fontSize = "14";

  # Nerd Font for build-time embedding
  nerdFont = pkgs.nerd-fonts.jetbrains-mono;
  fontDir = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono";

  # ===========================================================================
  # DEFAULTS (exported for module)
  # ===========================================================================

  defaults = {
    port = "7682";
    interface = "0.0.0.0";
    cwd = "/workspace";
    maxSessions = "10";
    idleTimeout = "3600000";  # 1 hour in ms
  };
  # ===========================================================================
  # GHOSTTY-WEB NPM PACKAGE (Frontend Assets)
  # ===========================================================================
  # Fetch pre-built distribution from npm (includes WASM binary)
  # Building from source requires Zig toolchain - avoid by using pre-built

  ghosttyWebPkg = pkgs.fetchzip {
    url = "https://registry.npmjs.org/ghostty-web/-/ghostty-web-0.4.0.tgz";
    hash = "sha256-ylBlhpFJaChMnNaSc+R/yvTLiDnjTH9Sz/HBr8CNU3k=";
    stripRoot = true;
  };

  # ===========================================================================
  # SERVER APPLICATION
  # ===========================================================================
  # Single derivation containing server.js + node_modules as siblings
  # This structure is REQUIRED for ESM module resolution
  #
  # Output structure:
  #   $out/bin/ghostty-web-server     (wrapper script)
  #   $out/lib/ghostty-web/
  #     ├── server.js                 (application entry)
  #     ├── index.html                (frontend template)
  #     ├── node_modules/             (dependencies - sibling to server.js)
  #     └── static/
  #         ├── ghostty-web.js        (WASM loader)
  #         └── ghostty-vt.wasm       (terminal core)

  ghosttyWebServer = pkgs.buildNpmPackage {
    pname = "ghostty-web-server";
    version = "1.0.0";

    src = ./.;

    # Hash for npm dependencies (node-pty + ws)
    # Regenerate with: nix-build -E 'let pkgs = import <nixpkgs> {}; in (import ./src/programs/ghostty-web { inherit pkgs; inherit (pkgs) lib; }).server'
    npmDepsHash = "sha256-hF4d0Gm+JklEOB6t/zMtTZHSl7Tnk2WehhE0iUFOQHw=";

    # Native module build requirements for node-pty
    nativeBuildInputs = with pkgs; [
      python3      # Required for node-gyp
      pkg-config
      makeWrapper
    ];

    # node-pty uses forkpty() on Linux which links against -lutil
    # This is provided by glibc, no explicit buildInput needed

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Create application directory structure
      mkdir -p $out/lib/ghostty-web/static
      mkdir -p $out/bin

      # Copy application code
      cp ${./server.js} $out/lib/ghostty-web/server.js

      # Copy node_modules (MUST be sibling of server.js for ESM resolution)
      cp -r node_modules $out/lib/ghostty-web/

      # =========================================================================
      # EMBED FONTS INTO INDEX.HTML (Same pattern as ttyd.nix)
      # =========================================================================
      # This ensures fonts are available BEFORE terminal measures metrics
      # Fixes "blocky" rendering caused by font loading race condition

      echo "Embedding Nerd Fonts into ghostty-web index.html..."

      # Verify font directory exists
      if [ ! -d "${fontDir}" ]; then
        echo "ERROR: Font directory not found: ${fontDir}"
        exit 1
      fi

      # Find font files
      REGULAR_FONT=$(find ${fontDir} -name "*Regular*.ttf" | head -1)
      BOLD_FONT=$(find ${fontDir} -name "*Bold*.ttf" | grep -v "Italic" | head -1)

      if [ -z "$REGULAR_FONT" ]; then
        echo "ERROR: Could not find Regular font in ${fontDir}"
        exit 1
      fi

      echo "Using fonts:"
      echo "  Regular: $REGULAR_FONT"
      echo "  Bold: $BOLD_FONT"

      # Copy index.html and make it writable
      cp ${./index.html} $out/lib/ghostty-web/static/index.html
      chmod +w $out/lib/ghostty-web/static/index.html

      # Generate embedded font CSS and inject into index.html
      EMBEDDED_FONTS="<!-- Embedded JetBrains Mono Nerd Font (build-time, airgap-safe) -->
        <style id=\"konductor-embedded-fonts\">
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: url('data:font/ttf;base64,$(base64 -w0 "$REGULAR_FONT")') format('truetype');
            font-weight: normal;
            font-style: normal;
          }"

      if [ -n "$BOLD_FONT" ]; then
        EMBEDDED_FONTS="$EMBEDDED_FONTS
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: url('data:font/ttf;base64,$(base64 -w0 "$BOLD_FONT")') format('truetype');
            font-weight: bold;
            font-style: normal;
          }"
      fi

      EMBEDDED_FONTS="$EMBEDDED_FONTS
        </style>"

      # Inject before </head> tag
      substituteInPlace $out/lib/ghostty-web/static/index.html \
        --replace '</head>' "$EMBEDDED_FONTS</head>"

      echo "Fonts embedded successfully"

      # =========================================================================
      # COPY REMAINING STATIC ASSETS
      # =========================================================================
      cp ${ghosttyWebPkg}/dist/ghostty-web.js $out/lib/ghostty-web/static/
      cp ${ghosttyWebPkg}/ghostty-vt.wasm $out/lib/ghostty-web/static/

      # Create wrapper with --chdir (CRITICAL for ESM resolution)
      # ESM ignores NODE_PATH; must set CWD to directory containing node_modules
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/ghostty-web-server \
        --add-flags "$out/lib/ghostty-web/server.js" \
        --chdir "$out/lib/ghostty-web" \
        --set GHOSTTY_WEB_STATIC "$out/lib/ghostty-web/static" \
        --set GHOSTTY_WEB_WASM "$out/lib/ghostty-web/static/ghostty-vt.wasm" \
        --set NODE_ENV "production"

      runHook postInstall
    '';

    meta = {
      description = "Ghostty web terminal server for Konductor";
      homepage = "https://github.com/coder/ghostty-web";
      license = lib.licenses.mit;
      mainProgram = "ghostty-web-server";
    };
  };

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Package list for inclusion in devshells/system packages
  packages = [ ghosttyWebServer ];

  # Server package for direct reference (used by NixOS module)
  server = ghosttyWebServer;

  # Individual components for testing/debugging
  components = {
    inherit ghosttyWebPkg;
  };

  # No shell hook needed - service is systemd-managed
  shellHook = "";

  # Environment variables (for manual testing in devshell)
  env = {
    GHOSTTY_WEB_STATIC = "${ghosttyWebServer}/lib/ghostty-web/static";
    GHOSTTY_WEB_WASM = "${ghosttyWebServer}/lib/ghostty-web/static/ghostty-vt.wasm";
  };

  # ===========================================================================
  # THEME AND CONFIG EXPORTS (for NixOS module)
  # ===========================================================================
  # Same pattern as ttyd - export theme for module to import

  # Theme export for NixOS module
  theme = catppuccinFrappe;

  # Font configuration export
  inherit fontFamily fontSize;

  # Default configuration export
  inherit defaults;
}
