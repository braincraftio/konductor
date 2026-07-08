# src/lib/theme.nix
# Catppuccin Frappé theme — Single Source of Truth
#
# Canonical palette: https://catppuccin.com/palette (Frappé flavor)
# Values verified against catppuccin/palette upstream JSON.
#
# Consumers:
#   src/programs/ttyd/default.nix   — xterm.js ITheme (via .xterm)
#   src/programs/tmux/default.nix   — F12 nested-toggle status colors
#   src/overlays/ttyd.nix           — overlay.ts toast colors (via .ui)
#   src/qcow2/default.nix           — vscode default settings reference
#
# Rule: no consumer writes a hex literal for a Catppuccin color.
# New consumers import this file and reference palette.<name>.

rec {
  flavor = "frappe";

  # ===========================================================================
  # Full Frappé palette (26 canonical colors)
  # ===========================================================================
  palette = {
    rosewater = "#f2d5cf";
    flamingo = "#eebebe";
    pink = "#f4b8e4";
    mauve = "#ca9ee6";
    red = "#e78284";
    maroon = "#ea999c";
    peach = "#ef9f76";
    yellow = "#e5c890";
    green = "#a6d189";
    teal = "#81c8be";
    sky = "#99d1db";
    sapphire = "#85c1dc";
    blue = "#8caaee";
    lavender = "#babbf1";
    text = "#c6d0f5";
    subtext1 = "#b5bfe2";
    subtext0 = "#a5adce";
    overlay2 = "#949cbb";
    overlay1 = "#838ba7";
    overlay0 = "#737994";
    surface2 = "#626880";
    surface1 = "#51576d";
    surface0 = "#414559";
    base = "#303446";
    mantle = "#292c3c";
    crust = "#232634";
  };

  # ===========================================================================
  # xterm.js ITheme mapping (ttyd, and any future xterm.js embed)
  # https://xtermjs.org/docs/api/terminal/interfaces/itheme/
  # ===========================================================================
  xterm = {
    # Base colors
    background = palette.base;
    foreground = palette.text;
    cursor = palette.rosewater;
    cursorAccent = palette.base;
    selectionBackground = palette.surface2;
    selectionForeground = palette.text;
    # ANSI Normal (0-7)
    black = palette.surface1;
    red = palette.red;
    green = palette.green;
    yellow = palette.yellow;
    blue = palette.blue;
    magenta = palette.mauve;
    cyan = palette.teal;
    white = palette.subtext1;
    # ANSI Bright (8-15)
    brightBlack = palette.surface2;
    brightRed = palette.red;
    brightGreen = palette.green;
    brightYellow = palette.yellow;
    brightBlue = palette.blue;
    brightMagenta = palette.pink;
    brightCyan = palette.sky;
    brightWhite = palette.text;
  };

  # ===========================================================================
  # Semantic UI roles (non-terminal chrome: toasts, popups, inactive states)
  # ===========================================================================
  ui = {
    toastBackground = palette.surface0;
    toastForeground = palette.text;
    inactiveForeground = palette.overlay0;
    inactiveBackground = palette.surface0;
    activeForeground = palette.text;
    activeBackground = palette.surface1;
    accent = palette.mauve;
  };
}
