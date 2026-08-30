# src/overlays/ttyd.nix
# Custom ttyd with embedded Nerd Fonts for airgapped operation
#
# ttyd embeds ALL frontend assets (HTML/CSS/JS) into the binary at build time.
# There is no runtime mechanism to inject fonts. This overlay patches the
# template.html before build to embed JetBrains Mono Nerd Font as base64.
#
# Research sources:
#   - tsl0922/ttyd: Frontend build embeds into html.h C header
#   - ryanoasis/nerd-fonts: Use "Nerd Font Mono" variant for terminal
#   - NixOS/nixpkgs: kitty terminal uses same pattern for font embedding
#
# Font is loaded from nixpkgs nerd-fonts.jetbrains-mono at BUILD time.
# When nerd-fonts updates, rebuilding ttyd picks up new version automatically.

self: super:
if !super.stdenv.hostPlatform.isLinux then
  { }
else
  let
    # Nerd Font package from nixpkgs
    nerdFont = self.nerd-fonts.jetbrains-mono;

    # Font file path (Mono variant for single-width terminal glyphs)
    fontDir = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono";

    # Catppuccin Frappé SSOT (src/lib/theme.nix) — overlay toast colors
    konductorTheme = import ../lib/theme.nix;

    # Yarn Berry offline cache for ttyd frontend rebuild
    yarn-berry = self.yarn-berry_3;
    ttydFrontendOfflineCache = yarn-berry.fetchYarnBerryDeps {
      yarnLock = "${super.ttyd.src}/html/yarn.lock";
      hash = "sha256-2VhypFRl195JJ9+AYDC/yZhLpFjKZcSLA1sZ25IYh1g=";
    };

  in
  {
    ttyd = super.ttyd.overrideAttrs (old: {
      pname = "ttyd-konductor";

      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
        self.nodejs
        yarn-berry
      ];

      postPatch = (old.postPatch or "") + ''
        echo "Embedding Nerd Fonts into ttyd template..."

        # Theme the OverlayAddon toasts ("Connection Closed", resize COLSxROWS,
        # copy scissors) to Catppuccin Frappé — upstream hardcodes light chrome
        # (#101010 on #f0f0f0) that flashbangs the dark theme.
        # SSOT: src/lib/theme.nix ui.toast*
        substituteInPlace html/src/components/terminal/xterm/addons/overlay.ts \
          --replace-fail "overlayNode.style.color = '#101010';" \
                         "overlayNode.style.color = '${konductorTheme.ui.toastForeground}';" \
          --replace-fail "overlayNode.style.backgroundColor = '#f0f0f0';" \
                         "overlayNode.style.backgroundColor = '${konductorTheme.ui.toastBackground}';"

        # Verify font directory exists
        if [ ! -d "${fontDir}" ]; then
          echo "ERROR: Font directory not found: ${fontDir}"
          echo "Available in nerd-fonts package:"
          find ${nerdFont}/share/fonts -type f -name "*.ttf" | head -20
          exit 1
        fi

        # Exact font files — deterministic selection.
        # Globs like *NerdFontMono-Regular.ttf match BOTH the ligature family
        # (JetBrainsMonoNerdFontMono-*) and the No-Ligatures family
        # (JetBrainsMonoNLNerdFontMono-*), and `find | head -1` returns
        # filesystem enumeration order — the embedded variant was luck.
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

        echo "Using fonts:"
        echo "  Regular:    $REGULAR_FONT"
        echo "  Bold:       $BOLD_FONT"
        echo "  Italic:     $ITALIC_FONT"
        echo "  BoldItalic: $BOLD_ITALIC_FONT"

        # Generate base64-encoded font CSS
        FONT_CSS="<style id=\"konductor-fonts\">"

        # Regular weight — local() preferred over embedded for better rendering
        FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: local(\"JetBrainsMono Nerd Font Mono\"),
                 local(\"JetBrainsMono NF Mono\"),
                 local(\"JetBrainsMonoNerdFontMono-Regular\"),
                 url(\"data:font/ttf;base64,$(base64 -w0 "$REGULAR_FONT")\") format(\"truetype\");
            font-weight: normal;
            font-style: normal;
            font-display: swap;
          }"

        # Bold weight
        FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: local(\"JetBrainsMono Nerd Font Mono Bold\"),
                 local(\"JetBrainsMono NF Mono Bold\"),
                 local(\"JetBrainsMonoNerdFontMono-Bold\"),
                 url(\"data:font/ttf;base64,$(base64 -w0 "$BOLD_FONT")\") format(\"truetype\");
            font-weight: bold;
            font-style: normal;
            font-display: swap;
          }"

        # Italic — real italic face; without it the browser synthesizes an
        # oblique from the Regular face (xterm.js sets font-style for italics)
        FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: local(\"JetBrainsMono Nerd Font Mono Italic\"),
                 local(\"JetBrainsMono NF Mono Italic\"),
                 local(\"JetBrainsMonoNerdFontMono-Italic\"),
                 url(\"data:font/ttf;base64,$(base64 -w0 "$ITALIC_FONT")\") format(\"truetype\");
            font-weight: normal;
            font-style: italic;
            font-display: swap;
          }"

        # Bold Italic
        FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: local(\"JetBrainsMono Nerd Font Mono Bold Italic\"),
                 local(\"JetBrainsMono NF Mono Bold Italic\"),
                 local(\"JetBrainsMonoNerdFontMono-BoldItalic\"),
                 url(\"data:font/ttf;base64,$(base64 -w0 "$BOLD_ITALIC_FONT")\") format(\"truetype\");
            font-weight: bold;
            font-style: italic;
            font-display: swap;
          }"

        # Hide the xterm.js viewport scrollbar. tmux manages scrollback
        # (copy-mode), so the browser scrollbar is redundant — and it renders
        # as default white chrome on the dark theme. scrollbar-width covers
        # Firefox, ::-webkit-scrollbar covers Chromium/WebKit.
        FONT_CSS="$FONT_CSS
          .xterm .xterm-viewport {
            scrollbar-width: none;
            -ms-overflow-style: none;
          }
          .xterm .xterm-viewport::-webkit-scrollbar {
            width: 0;
            height: 0;
            display: none;
          }
        </style>"

        # OSC 52 clipboard handler for tmux copy-mode integration
        # tmux with mouse-on captures all mouse events, preventing browser text
        # selection. tmux-yank pipes selections via copy-pipe to osc52clip which
        # emits OSC 52 escape sequences. This handler intercepts those sequences
        # in xterm.js and writes the decoded text to the browser clipboard via
        # navigator.clipboard.writeText() with a textarea fallback.
        OSC52_SCRIPT='<script id="konductor-osc52">(function(){var i=setInterval(function(){if(window.term&&window.term.parser){clearInterval(i);window.term.parser.registerOscHandler(52,function(d){var p=d.split(";");if(p.length<2)return false;var b=p.slice(1).join(";");if(b==="?")return true;try{var t=new TextDecoder().decode(Uint8Array.from(atob(b),function(c){return c.charCodeAt(0)}));if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).catch(function(){_fc(t)})}else{_fc(t)}}catch(e){}return true});function _fc(t){var a=document.createElement("textarea");a.value=t;a.style.position="fixed";a.style.left="-9999px";document.body.appendChild(a);a.select();try{document.execCommand("copy")}catch(e){}document.body.removeChild(a)}}},100)})();</script>'

        # Inject fonts and OSC 52 handler into template.html before </head>
        if [ -f html/src/template.html ]; then
          substituteInPlace html/src/template.html \
            --replace-fail '</head>' "$FONT_CSS$OSC52_SCRIPT</head>"
          echo "Fonts and OSC 52 clipboard handler injected into html/src/template.html"
        else
          echo "ERROR: html/src/template.html not found"
          exit 1
        fi
      '';

      # Rebuild frontend with patched template.html
      # The yarn project is in html/ subdirectory, not the source root.
      # yarnBerryConfigHook assumes root — we run yarn install manually.
      preBuild = ''
        echo "Installing ttyd frontend dependencies..."
        cd $NIX_BUILD_TOP/source/html

        # Replicate yarnBerryConfigHook for subdirectory yarn project
        export HOME=$(mktemp -d)
        YARN_IGNORE_PATH=1 yarn config set enableTelemetry false
        YARN_IGNORE_PATH=1 yarn config set enableGlobalCache false

        rm -rf ./.yarn/cache
        mkdir -p ./.yarn
        cp -r --reflink=auto ${ttydFrontendOfflineCache}/cache ./.yarn/cache
        chmod u+w -R ./.yarn/cache
        if [ -d ${ttydFrontendOfflineCache}/checkouts ]; then
          cp -r --reflink=auto ${ttydFrontendOfflineCache}/checkouts ./.yarn/checkouts
          chmod u+w -R ./.yarn/checkouts
        fi

        YARN_IGNORE_PATH=1 yarn install --mode=skip-build --inline-builds
        patchShebangs node_modules
        YARN_IGNORE_PATH=1 yarn install --inline-builds

        echo "Building ttyd frontend (webpack + gulp)..."
        NODE_ENV=production npx webpack
        npx gulp

        cd $NIX_BUILD_TOP/source/build
        echo "Frontend rebuilt — src/html.h regenerated"
      '';

      meta = old.meta // {
        description = "ttyd with embedded JetBrains Mono Nerd Font for Konductor";
      };
    });
  }
