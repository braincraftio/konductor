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

    -- Note: vim.ui.select is handled by snacks.picker (ui_select = true in plugins.nix)
    -- Note: Dashboard highlights are theme-aware via catppuccin custom_highlights in default.nix

    -- =========================================================================
    -- CUSTOM TERMINAL TOGGLES (via Snacks.terminal)
    -- =========================================================================
    -- Note: LazyGit is handled by snacks.lazygit (enabled in plugins.nix)
    -- All toggles namespaced under Konductor to avoid global pollution

    Konductor = Konductor or {}

    -- Btop - system monitor (float, large)
    Konductor.btop_toggle = function()
      Snacks.terminal.toggle("btop", {
        win = {
          position = "float",
          width = 0.9,
          height = 0.9,
          border = "rounded",
        },
      })
    end

    -- Python REPL (bottom split)
    Konductor.python_toggle = function()
      Snacks.terminal.toggle("python3", {
        win = {
          position = "bottom",
          height = 0.3,
        },
      })
    end

    -- Node REPL (bottom split)
    Konductor.node_toggle = function()
      Snacks.terminal.toggle("node", {
        win = {
          position = "bottom",
          height = 0.3,
        },
      })
    end

    -- Copilot CLI (vertical split on right)
    Konductor.copilot_cli_toggle = function()
      Snacks.terminal.toggle("copilot", {
        cwd = vim.fn.getcwd(),
        win = {
          position = "right",
          width = 0.4,
        },
      })
    end

    -- Codex CLI (vertical split on right)
    Konductor.codex_cli_toggle = function()
      Snacks.terminal.toggle("codex", {
        cwd = vim.fn.getcwd(),
        win = {
          position = "right",
          width = 0.4,
        },
      })
    end
  '';
}
