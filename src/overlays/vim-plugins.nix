# src/overlays/vim-plugins.nix
# Fixes for vim plugin builds and upstream bug patches
#
# lualine-nvim: Disable tests that require git repository context.
#   The luarocks builder runs integration tests in nix sandbox where
#   git commands fail (no .git directory).
#
# claude-code-nvim: Three upstream bugs patched (greggh/claude-code.nvim):
#   1. E444 "Cannot close last window" — nvim_win_close without pcall
#   2. TermClose "Invalid buffer id" — missing nvim_buf_is_valid guard
#   3. Duplicate terminal buffer in split mode — :terminal on inherited
#      buffer instead of nvim_create_buf + termopen
#   See patches/claude-code-nvim-terminal-fixes.patch for details.

_final: prev: {
  vimPlugins = prev.vimPlugins // {
    lualine-nvim = prev.lib.dontCheck prev.vimPlugins.lualine-nvim;

    claude-code-nvim = prev.vimPlugins.claude-code-nvim.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/claude-code-nvim-terminal-fixes.patch
      ];
    });
  };
}
