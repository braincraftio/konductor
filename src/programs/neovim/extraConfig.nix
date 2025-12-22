# src/programs/neovim/extraConfig.nix
# Raw Lua configuration (minimal - only what can't be done via nixvim options)
{ }:

{
  extraConfigLuaPre = ''
    -- Ensure Snacks is globally available
    _G.Snacks = require("snacks")
  '';

  extraConfigLua = ''
    -- Debug helpers
    _G.dd = function(...)
      Snacks.debug.inspect(...)
    end
    _G.bt = function()
      Snacks.debug.backtrace()
    end
    vim.print = _G.dd

    -- Override vim.ui.select with Snacks picker (safer than input override)
    vim.ui.select = function(items, opts, on_choice)
      Snacks.picker.select(items, opts, on_choice)
    end
  '';
}
