# src/config/opencode/default.nix
# OpenCode configuration values
#
# Project-level config lives in opencode.json at repo root.
# OpenCode automatically merges project config with global (~/.config/opencode/).
#
# This file exports values for reference by other Nix expressions.

_:

{
  # Catppuccin theme for visual consistency with Neovim
  themeName = "catppuccin";

  # Free model from OpenCode Zen for title generation (no API key required)
  smallModel = "opencode/gpt-5-nano";

  # No shell hook needed - opencode.json in project root handles config
  shellHook = "";

  # No environment variables needed
  env = { };
}
