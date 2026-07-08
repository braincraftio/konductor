# src/programs/restty-web/default.nix
# Restty Web Terminal - PTY server package for Konductor
#
# Provides browser-accessible terminal via HTTP + WebSocket.
# Uses restty (WebGPU/WebGL2 WASM terminal renderer) for high-fidelity rendering.
# Designed for KubeVirt VM deployment behind Envoy Gateway (OIDC).
#
# FONT EMBEDDING:
#   Fonts are embedded into index.html at build time (same pattern as ghostty-web/ttyd).
#   Uses JetBrains Mono Nerd Font Mono from nixpkgs nerd-fonts.
#
# ESM Module Resolution:
# - Node.js ESM ignores NODE_PATH environment variable
# - Solution: Place server.js and node_modules as siblings
# - Use makeWrapper --chdir to set CWD to application directory
#
# Dependencies:
# - node-pty (microsoft/node-pty v1.1.0) - PTY management, built from source
# - ws - WebSocket server
# - restty - WASM terminal frontend (fetched from npm)

{ pkgs, lib, ... }:

let
  # ===========================================================================
  # THEME (selected by name — restty ships 300+ builtin Ghostty themes)
  # ===========================================================================
  # Palette colors are NOT duplicated here.  The frontend calls
  # getBuiltinTheme(themeName) at runtime so upstream theme updates
  # propagate automatically without touching Nix code.
  themeName = "Catppuccin Frappe";

  # ===========================================================================
  # FONT CONFIGURATION
  # ===========================================================================
  fontFamily = "'JetBrainsMono Nerd Font Mono', 'JetBrains Mono', monospace";
  fontSize = "14";

  nerdFont = pkgs.nerd-fonts.jetbrains-mono;
  fontDir = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono";

  # ===========================================================================
  # DEFAULTS (exported for module)
  # ===========================================================================
  defaults = {
    port = "7685";
    interface = "0.0.0.0";
    cwd = "/workspace";
    maxSessions = "10";
    idleTimeout = "3600000";
  };

  # ===========================================================================
  # RESTTY NPM PACKAGE (Frontend Assets)
  # ===========================================================================
  # Fetch pre-built distribution from npm (includes embedded WASM binary)
  # The WASM (libghostty-vt) is embedded as base64 in the JS bundle

  resttyPkg = pkgs.fetchzip {
    url = "https://registry.npmjs.org/restty/-/restty-0.1.27.tgz";
    hash = "sha256-Mkl3kEkpKaNx9K5vyc19PI0CakQGZWkFOg+f8oKFUbw=";
    stripRoot = true;
  };

  # ===========================================================================
  # SERVER APPLICATION
  # ===========================================================================
  # Output structure:
  #   $out/bin/restty-web-server      (wrapper script)
  #   $out/lib/restty-web/
  #     ├── server.js                 (application entry)
  #     ├── node_modules/             (dependencies - sibling to server.js)
  #     └── static/
  #         ├── index.html            (frontend with embedded fonts)
  #         └── restty/               (restty library dist — ESM with chunks)

  resttyWebServer = pkgs.buildNpmPackage {
    pname = "restty-web-server";
    version = "1.0.0";

    src = ./.;

    # Hash for npm dependencies (node-pty + ws)
    # Same deps as ghostty-web — hash should be identical
    npmDepsHash = "sha256-hF4d0Gm+JklEOB6t/zMtTZHSl7Tnk2WehhE0iUFOQHw=";

    nativeBuildInputs = with pkgs; [
      python3
      pkg-config
      makeWrapper
    ];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/restty-web/static/restty
      mkdir -p $out/bin

      # Copy application code
      cp ${./server.js} $out/lib/restty-web/server.js

      # Copy node_modules (MUST be sibling of server.js for ESM resolution)
      cp -r node_modules $out/lib/restty-web/

      # =========================================================================
      # EMBED FONTS INTO INDEX.HTML (Same pattern as ghostty-web/ttyd)
      # =========================================================================

      echo "Embedding Nerd Fonts into restty-web index.html..."

      if [ ! -d "${fontDir}" ]; then
        echo "ERROR: Font directory not found: ${fontDir}"
        exit 1
      fi

      # Exact font files — deterministic selection (globs match Propo/NL
      # families; find|head-1 order is filesystem-dependent)
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

      cp ${./index.html} $out/lib/restty-web/static/index.html
      chmod +w $out/lib/restty-web/static/index.html

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
      substituteInPlace $out/lib/restty-web/static/index.html \
        --replace-fail '@konductorEmbeddedFonts@' "$EMBEDDED_FONTS"

      echo "Fonts embedded successfully"

      # =========================================================================
      # COPY RESTTY FRONTEND ASSETS
      # =========================================================================
      # Copy entire dist/ directory — restty.js imports from chunk-*.js files
      # ESM requires all chunks to be co-located for relative imports
      cp -r ${resttyPkg}/dist/* $out/lib/restty-web/static/restty/

      # Create wrapper with --chdir (CRITICAL for ESM resolution)
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/restty-web-server \
        --add-flags "$out/lib/restty-web/server.js" \
        --chdir "$out/lib/restty-web" \
        --set RESTTY_WEB_STATIC "$out/lib/restty-web/static" \
        --set NODE_ENV "production"

      runHook postInstall
    '';

    meta = {
      description = "Restty web terminal server for Konductor";
      homepage = "https://github.com/wiedymi/restty";
      license = lib.licenses.mit;
      mainProgram = "restty-web-server";
    };
  };

in
{
  packages = [ resttyWebServer ];
  server = resttyWebServer;

  components = {
    inherit resttyPkg;
  };

  shellHook = "";

  env = {
    RESTTY_WEB_STATIC = "${resttyWebServer}/lib/restty-web/static";
  };

  theme = themeName;
  inherit fontFamily fontSize;
  inherit defaults;
}
