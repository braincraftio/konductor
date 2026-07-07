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
if !super.stdenv.isLinux then
  { }
else
  let
    # Nerd Font package from nixpkgs
    nerdFont = self.nerd-fonts.jetbrains-mono;

    # Font file path (Mono variant for single-width terminal glyphs)
    # Structure: $out/share/fonts/truetype/NerdFonts/<fontDirName>/
    fontDir = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono";

  in
  {
    # Override ttyd with embedded fonts
    ttyd = super.ttyd.overrideAttrs (old: {
      pname = "ttyd-konductor";

      # Patch template.html to inject @font-face declarations
      postPatch = (old.postPatch or "") + ''
        echo "Embedding Nerd Fonts into ttyd template..."

        # Verify font directory exists
        if [ ! -d "${fontDir}" ]; then
          echo "ERROR: Font directory not found: ${fontDir}"
          echo "Available in nerd-fonts package:"
          find ${nerdFont}/share/fonts -type f -name "*.ttf" | head -20
          exit 1
        fi

        # Find the Mono variant fonts (single-width glyphs for terminal use)
        # Must match NerdFontMono, NOT NerdFontPropo (proportional) or NerdFont (patched)
        REGULAR_FONT=$(find ${fontDir} -name "*NerdFontMono-Regular.ttf" | head -1)
        BOLD_FONT=$(find ${fontDir} -name "*NerdFontMono-Bold.ttf" | head -1)

        if [ -z "$REGULAR_FONT" ]; then
          echo "ERROR: Could not find Regular font in ${fontDir}"
          ls -la ${fontDir}/
          exit 1
        fi

        echo "Using fonts:"
        echo "  Regular: $REGULAR_FONT"
        echo "  Bold: $BOLD_FONT"

        # Generate base64-encoded font CSS
        FONT_CSS="<style id=\"konductor-fonts\">"

        # Regular weight
        FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: url(\"data:font/ttf;base64,$(base64 -w0 "$REGULAR_FONT")\") format(\"truetype\");
            font-weight: normal;
            font-style: normal;
          }"

        # Bold weight (if available)
        if [ -n "$BOLD_FONT" ]; then
          FONT_CSS="$FONT_CSS
          @font-face {
            font-family: \"JetBrainsMono Nerd Font Mono\";
            src: url(\"data:font/ttf;base64,$(base64 -w0 "$BOLD_FONT")\") format(\"truetype\");
            font-weight: bold;
            font-style: normal;
          }"
        fi

        FONT_CSS="$FONT_CSS
        </style>"

        # OSC 52 clipboard handler for tmux copy-mode integration
        # tmux with mouse-on captures all mouse events, preventing browser text
        # selection. tmux-yank pipes selections via copy-pipe to osc52clip which
        # emits OSC 52 escape sequences. This handler intercepts those sequences
        # in xterm.js and writes the decoded text to the browser clipboard via
        # navigator.clipboard.writeText() with a textarea fallback.
        OSC52_SCRIPT='<script id="konductor-osc52">(function(){var i=setInterval(function(){if(window.term&&window.term.parser){clearInterval(i);window.term.parser.registerOscHandler(52,function(d){var p=d.split(";");if(p.length<2)return false;var b=p.slice(1).join(";");if(b==="?")return true;try{var t=atob(b);if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).catch(function(){_fc(t)})}else{_fc(t)}}catch(e){}return true});function _fc(t){var a=document.createElement("textarea");a.value=t;a.style.position="fixed";a.style.left="-9999px";document.body.appendChild(a);a.select();try{document.execCommand("copy")}catch(e){}document.body.removeChild(a)}}},100)})();</script>'

        # Inject fonts and OSC 52 handler into template.html before </head>
        if [ -f html/src/template.html ]; then
          substituteInPlace html/src/template.html \
            --replace '</head>' "$FONT_CSS$OSC52_SCRIPT</head>"
          echo "Fonts and OSC 52 clipboard handler injected into html/src/template.html"
        else
          echo "ERROR: html/src/template.html not found"
          find . -name "template.html" -o -name "*.html" | head -10
          exit 1
        fi
      '';

      meta = old.meta // {
        description = "ttyd with embedded JetBrains Mono Nerd Font for Konductor";
      };
    });
  }
