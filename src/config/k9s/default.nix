# src/config/k9s/default.nix
# k9s Kubernetes TUI wrapper with Catppuccin Frappe theme
#
# Uses catppuccin/nix flake for theme files (Nix-native approach).
# K9S_SKIN only accepts skin names, not paths - k9s always prepends
# AppSkinsDir and appends .yaml. Wrapper symlinks theme to skins dir.
#
# Theme: Catppuccin Frappe (matches tmux, neovim, ttyd, starship)
# Source: github:catppuccin/nix (packages.${system}.sources.k9s)
#
# Reference:
#   https://k9scli.io/topics/config/
#   https://catppuccin.com/palette

{ pkgs, catppuccinSources }:

let
  # ===========================================================================
  # THEME CONFIGURATION
  # ===========================================================================
  # Theme file from catppuccin/nix flake (SSOT - no local copy)
  # catppuccinSources.sources.k9s contains all k9s theme files
  #
  skinFile = "${catppuccinSources.sources.k9s}/dist/catppuccin-frappe.yaml";

  # ===========================================================================
  # WRAPPED K9S
  # ===========================================================================
  # Wrapper that symlinks theme to ~/.config/k9s/skins/ and sets K9S_SKIN.
  #
  # K9S_SKIN does NOT support absolute paths - it always prepends AppSkinsDir
  # and appends .yaml. So we must symlink the theme file to the skins dir.
  #
  # This approach:
  #   - Symlinks theme from nix store to user's skins directory
  #   - Sets K9S_SKIN to theme name (not path)
  #   - Preserves default XDG paths for writes
  #
  wrappedK9s = pkgs.writeShellApplication {
    name = "k9s";
    runtimeInputs = [ pkgs.unstable.k9s pkgs.coreutils ];
    text = ''
      # Ensure skins directory exists
      SKINS_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/k9s/skins"
      mkdir -p "$SKINS_DIR"

      # Symlink theme from nix store (idempotent)
      THEME_LINK="$SKINS_DIR/catppuccin-frappe.yaml"
      if [[ ! -L "$THEME_LINK" ]] || [[ "$(readlink "$THEME_LINK")" != "${skinFile}" ]]; then
        ln -sf "${skinFile}" "$THEME_LINK"
      fi

      export K9S_SKIN="catppuccin-frappe"
      exec k9s "$@"
    '';
  };

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Wrapped k9s with Catppuccin Frappe theme
  package = wrappedK9s;

  # Unwrapped k9s for debugging or when user wants default behavior
  unwrapped = pkgs.unstable.k9s;

  # Skin file path (for reference/debugging)
  inherit skinFile;

  # Metadata
  meta = {
    description = "k9s Kubernetes TUI with Catppuccin Frappe theme";
    configurable = true;
  };
}
