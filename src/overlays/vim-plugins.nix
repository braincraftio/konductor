# src/overlays/vim-plugins.nix
# Fixes for vim plugin builds
#
# lualine-nvim: Disable tests that require git repository context
# The luarocks builder runs integration tests in nix sandbox where
# git commands fail (no .git directory). These are integration tests
# that should run in actual neovim environment, not during package build.

_final: prev: {
  vimPlugins = prev.vimPlugins // {
    lualine-nvim = prev.lib.dontCheck prev.vimPlugins.lualine-nvim;
  };
}
