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
  # SSOT: src/lib/theme.nix — do not add hex literals here.
  # Note: selectionBackground unified to solid surface2 (was rgba overlay1
  # @ 30%) for parity with ttyd's xterm.js selection rendering.

  konductorTheme = import ../../lib/theme.nix;
  catppuccinFrappe = konductorTheme.xterm;

  # CSS custom properties (--ctp-*) generated from the palette, injected
  # into index.html's :root at build time (@konductorThemeCssVars@).
  themeCssVars = lib.concatStringsSep "\n      " (
    lib.mapAttrsToList (name: value: "--ctp-${name}: ${value};") konductorTheme.palette
  );

  # xterm.js ITheme JSON — injected into the Terminal() constructor
  # at build time (@konductorTerminalThemeJson@). Eliminates the 20
  # hardcoded hex values that were an SSOT violation (Finding 3).
  terminalThemeJson = builtins.toJSON konductorTheme.xterm;

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
    idleTimeout = "3600000"; # 1 hour in ms
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
    # Regenerate: set to pkgs.lib.fakeHash, rebuild, copy the "got:" hash:
    #   nix build --impure --expr '((import ./src/programs/ghostty-web) {
    #     pkgs = (builtins.getFlake ("path:" + toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux;
    #     inherit ((builtins.getFlake ("path:" + toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux) lib; }).server'
    npmDepsHash = "sha256-hF4d0Gm+JklEOB6t/zMtTZHSl7Tnk2WehhE0iUFOQHw=";

    # Native module build requirements for node-pty
    nativeBuildInputs = with pkgs; [
      python3 # Required for node-gyp
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

      # Exact font files — deterministic selection. Globs (*Regular*.ttf)
      # match the Propo (proportional) and NL (no-ligature) families too,
      # and `find | head -1` returns filesystem enumeration order.
      REGULAR_FONT="${fontDir}/JetBrainsMonoNerdFontMono-Regular.ttf"
      BOLD_FONT="${fontDir}/JetBrainsMonoNerdFontMono-Bold.ttf"
      ITALIC_FONT="${fontDir}/JetBrainsMonoNerdFontMono-Italic.ttf"
      BOLD_ITALIC_FONT="${fontDir}/JetBrainsMonoNerdFontMono-BoldItalic.ttf"
      for f in "$REGULAR_FONT" "$BOLD_FONT" "$ITALIC_FONT" "$BOLD_ITALIC_FONT"; do
        if [ ! -f "$f" ]; then
          echo "ERROR: Font file not found: $f"
          ls -la ${fontDir}/
          exit 1
        fi
      done

      # Copy index.html and make it writable
      cp ${./index.html} $out/lib/ghostty-web/static/index.html
      chmod +w $out/lib/ghostty-web/static/index.html

      # Theme CSS variables from src/lib/theme.nix (SSOT)
      substituteInPlace $out/lib/ghostty-web/static/index.html \
        --replace-fail '@konductorThemeCssVars@' '${themeCssVars}'

      # Terminal theme JSON from src/lib/theme.nix (SSOT)
      substituteInPlace $out/lib/ghostty-web/static/index.html \
        --replace-fail '@konductorTerminalThemeJson@' '${terminalThemeJson}'

      # Generate embedded font CSS and inject into index.html.
      # local() preferred over embedded (OS rasterizer, full hinting);
      # embedded base64 is the airgap fallback. font-display: swap avoids FOIT.
      EMBEDDED_FONTS="<!-- Embedded JetBrains Mono Nerd Font (build-time, airgap-safe) -->
        <style id=\"konductor-embedded-fonts\">
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: local('JetBrainsMono Nerd Font Mono'),
                 local('JetBrainsMonoNerdFontMono-Regular'),
                 url('data:font/ttf;base64,$(base64 -w0 "$REGULAR_FONT")') format('truetype');
            font-weight: normal;
            font-style: normal;
            font-display: swap;
          }
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: local('JetBrainsMono Nerd Font Mono Bold'),
                 local('JetBrainsMonoNerdFontMono-Bold'),
                 url('data:font/ttf;base64,$(base64 -w0 "$BOLD_FONT")') format('truetype');
            font-weight: bold;
            font-style: normal;
            font-display: swap;
          }
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: local('JetBrainsMono Nerd Font Mono Italic'),
                 local('JetBrainsMonoNerdFontMono-Italic'),
                 url('data:font/ttf;base64,$(base64 -w0 "$ITALIC_FONT")') format('truetype');
            font-weight: normal;
            font-style: italic;
            font-display: swap;
          }
          @font-face {
            font-family: 'JetBrainsMono Nerd Font Mono';
            src: local('JetBrainsMono Nerd Font Mono Bold Italic'),
                 local('JetBrainsMonoNerdFontMono-BoldItalic'),
                 url('data:font/ttf;base64,$(base64 -w0 "$BOLD_ITALIC_FONT")') format('truetype');
            font-weight: bold;
            font-style: italic;
            font-display: swap;
          }
        </style>"

      # Inject at the explicit placeholder (not the closing-head tag —
      # substituteInPlace replaces every occurrence of its pattern, so
      # structural HTML tokens are unsafe anchors)
      substituteInPlace $out/lib/ghostty-web/static/index.html \
        --replace-fail '@konductorEmbeddedFonts@' "$EMBEDDED_FONTS"

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
