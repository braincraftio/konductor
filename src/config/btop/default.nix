# src/config/btop/default.nix
# btop system monitor with Catppuccin Frappe theme
#
# Uses catppuccin/nix flake for theme files (Nix-native approach).
# btop reads themes from ~/.config/btop/themes/ directory.
# Wrapper symlinks theme and sets color_theme in btop.conf.
#
# Theme: Catppuccin Frappe (matches tmux, neovim, ttyd, k9s, starship)
# Source: github:catppuccin/nix (packages.${system}.sources.btop)
#
# Reference:
#   https://github.com/aristocratos/btop
#   https://catppuccin.com/palette

{ pkgs, catppuccinSources }:

let
  # ===========================================================================
  # THEME CONFIGURATION
  # ===========================================================================
  # Theme file from catppuccin/nix flake (SSOT - no local copy)
  # catppuccinSources.sources.btop contains all btop theme files
  #
  themeFile = "${catppuccinSources.sources.btop}/themes/catppuccin_frappe.theme";

  # ===========================================================================
  # WRAPPED BTOP
  # ===========================================================================
  # Wrapper that symlinks theme to ~/.config/btop/themes/ and sets
  # color_theme in btop.conf.
  #
  wrappedBtop = pkgs.writeShellApplication {
    name = "btop";
    runtimeInputs = [ pkgs.btop pkgs.coreutils ];
    text = ''
      # Ensure themes directory exists
      THEMES_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/btop/themes"
      CONF_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/btop"
      mkdir -p "$THEMES_DIR"

      # Symlink theme from nix store (idempotent)
      THEME_LINK="$THEMES_DIR/catppuccin_frappe.theme"
      if [[ ! -L "$THEME_LINK" ]] || [[ "$(readlink "$THEME_LINK")" != "${themeFile}" ]]; then
        ln -sf "${themeFile}" "$THEME_LINK"
      fi

      # Set theme in btop.conf if not already set
      CONF_FILE="$CONF_DIR/btop.conf"
      if [[ -f "$CONF_FILE" ]]; then
        if ! grep -q 'color_theme.*catppuccin_frappe' "$CONF_FILE"; then
          sed -i 's|^color_theme = .*|color_theme = "catppuccin_frappe"|' "$CONF_FILE"
        fi
      else
        echo 'color_theme = "catppuccin_frappe"' > "$CONF_FILE"
      fi

      exec btop "$@"
    '';
  };

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Wrapped btop with Catppuccin Frappe theme
  package = wrappedBtop;

  # Unwrapped btop for debugging or when user wants default behavior
  unwrapped = pkgs.btop;

  # Theme file path (for reference/debugging)
  inherit themeFile;

  # Metadata
  meta = {
    description = "btop system monitor with Catppuccin Frappe theme";
    configurable = true;
  };
}
