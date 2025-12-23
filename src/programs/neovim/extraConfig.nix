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

    -- =========================================================================
    -- DASHBOARD HIGHLIGHT REFINEMENTS
    -- =========================================================================
    -- Catppuccin Macchiato palette reference:
    -- mauve=#c6a0f6, blue=#8aadf4, sapphire=#7dc4e4, teal=#8bd5ca
    -- green=#a6da95, yellow=#eed49f, peach=#f5a97f, red=#ed8796
    -- text=#cad3f5, subtext1=#b8c0e0, overlay0=#6e738d, surface0=#363a4f

    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        -- Keys: Prominent button-like with background (mauve)
        vim.api.nvim_set_hl(0, "SnacksDashboardKey", {
          fg = "#181926",  -- Dark text on light bg
          bg = "#c6a0f6",  -- Mauve background
          bold = true,
        })

        -- Descriptions: Rich gold/yellow for prominence
        vim.api.nvim_set_hl(0, "SnacksDashboardDesc", {
          fg = "#eed49f",  -- Yellow/gold - stands out
          bold = true,
        })

        -- Icons: Bright sapphire blue
        vim.api.nvim_set_hl(0, "SnacksDashboardIcon", {
          fg = "#7dc4e4",  -- Sapphire
        })

        -- Section titles: Bold, distinct (teal)
        vim.api.nvim_set_hl(0, "SnacksDashboardTitle", {
          fg = "#8bd5ca",
          bold = true,
        })

        -- Header: Brand color (blue)
        vim.api.nvim_set_hl(0, "SnacksDashboardHeader", {
          fg = "#8aadf4",
        })

        -- Footer/Separator: Subtle (overlay)
        vim.api.nvim_set_hl(0, "SnacksDashboardFooter", {
          fg = "#6e738d",
        })

        -- Files: Clean readable text
        vim.api.nvim_set_hl(0, "SnacksDashboardFile", {
          fg = "#cad3f5",
        })

        -- Directories: Dimmed for hierarchy
        vim.api.nvim_set_hl(0, "SnacksDashboardDir", {
          fg = "#8087a2",
        })

        -- Special elements (numbers): Peach accent
        vim.api.nvim_set_hl(0, "SnacksDashboardSpecial", {
          fg = "#f5a97f",
          bold = true,
        })
      end,
    })

    -- Apply immediately for current colorscheme
    vim.cmd("doautocmd ColorScheme")

    -- =========================================================================
    -- CUSTOM TERMINAL TOGGLES (via Snacks.terminal)
    -- =========================================================================
    -- Note: LazyGit is handled by snacks.lazygit (enabled in plugins.nix)

    -- Btop - system monitor (float, large)
    function _btop_toggle()
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
    function _python_toggle()
      Snacks.terminal.toggle("python3", {
        win = {
          position = "bottom",
          height = 0.3,
        },
      })
    end

    -- Node REPL (bottom split)
    function _node_toggle()
      Snacks.terminal.toggle("node", {
        win = {
          position = "bottom",
          height = 0.3,
        },
      })
    end

    -- Copilot CLI (vertical split on right)
    function _copilot_cli_toggle()
      Snacks.terminal.toggle("copilot", {
        cwd = vim.fn.getcwd(),
        win = {
          position = "right",
          width = 0.4,
        },
      })
    end

    -- Codex CLI (vertical split on right)
    function _codex_cli_toggle()
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
