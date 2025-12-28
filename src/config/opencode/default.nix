# src/config/opencode/default.nix
# OpenCode theme configuration - Catppuccin
#
# Uses OpenCode's built-in catppuccin theme for visual consistency
# with the Neovim catppuccin-frappe setup.
#
# Available themes: opencode, catppuccin, dracula, flexoki, gruvbox,
#                   monokai, onedark, tokyonight, tron

{ pkgs }:

let
  themeName = "catppuccin";
in
{
  inherit themeName;

  # Shell hook to set theme in opencode config if not already configured
  shellHook = ''
    # Configure OpenCode catppuccin theme
    _opencode_config="$HOME/.config/opencode/opencode.json"
    if [ -f "$_opencode_config" ]; then
      # Check if theme is already set to catppuccin
      if ! grep -q '"theme".*"${themeName}"' "$_opencode_config" 2>/dev/null; then
        # Update theme in existing config (requires jq)
        if command -v jq &>/dev/null; then
          _tmp=$(mktemp)
          jq '.tui.theme = "${themeName}"' "$_opencode_config" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_opencode_config" || rm -f "$_tmp"
        fi
      fi
    else
      # Create minimal config with theme
      mkdir -p "$(dirname "$_opencode_config")"
      echo '{"$schema": "https://opencode.ai/config.json", "tui": {"theme": "${themeName}"}}' > "$_opencode_config"
    fi
    unset _opencode_config _tmp
  '';

  # Environment variables (none needed for theme)
  env = { };
}
