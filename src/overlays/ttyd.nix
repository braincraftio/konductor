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

let
  # Nerd Font package from nixpkgs
  nerdFont = self.nerd-fonts.jetbrains-mono;

  # Font file path (Mono variant for single-width terminal glyphs)
  # Structure: $out/share/fonts/truetype/NerdFonts/<fontDirName>/
  fontDir = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono";

  # CSS @font-face declaration template
  # Using ttf format for broad browser compatibility
  # font-family name must match what we pass to xterm.js via -t fontFamily
  fontFaceCSS = fontFile: fontWeight: fontStyle: ''
    @font-face {
      font-family: "JetBrainsMono Nerd Font Mono";
      src: url("data:font/ttf;base64,$(base64 -w0 ${fontDir}/${fontFile})") format("truetype");
      font-weight: ${fontWeight};
      font-style: ${fontStyle};
    }
  '';

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

      # Find the Regular font file (may have different naming conventions)
      REGULAR_FONT=$(find ${fontDir} -name "*Regular*.ttf" -o -name "*-Regular.ttf" | head -1)
      BOLD_FONT=$(find ${fontDir} -name "*Bold*.ttf" -o -name "*-Bold.ttf" | grep -v "Italic" | head -1)

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

      # Inject into template.html before </head>
      # The template has: <title>ttyd - Terminal</title> then CSS links
      if [ -f html/src/template.html ]; then
        substituteInPlace html/src/template.html \
          --replace '</head>' "$FONT_CSS</head>"
        echo "Fonts injected into html/src/template.html"
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
