# src/programs/neovim/extraConfig.nix
# Raw Lua configuration (minimal - only what can't be done via nixvim options)
{ }:

{
  extraConfigLuaPre = ''
    -- Ensure Snacks is globally available
    _G.Snacks = require("snacks")

    -- =========================================================================
    -- OPENCODE CONFIGURATION (must be set before plugin loads)
    -- =========================================================================
    -- opencode.nvim reads vim.g.opencode_opts on init
    -- Schema: port, auto_reload, auto_fallback_to_embedded, prompts, contexts, input, terminal
    vim.g.opencode_opts = {
      -- Automatically reload buffers when opencode edits files
      auto_reload = true,

      -- Launch embedded opencode terminal if no server found
      auto_fallback_to_embedded = true,

      -- Terminal window options (snacks.terminal.Opts)
      terminal = {
        win = {
          position = "right",
          width = 0.4,
        },
      },

      -- Built-in prompts with context injection
      prompts = {
        review = {
          prompt = "Review @this for correctness, readability, and potential issues. Be thorough but concise.",
          description = "Code review",
        },
        explain = {
          prompt = "Explain @this and its context. What does it do and why?",
          description = "Explain code",
        },
        document = {
          prompt = "Add clear documentation comments to @this following language conventions.",
          description = "Document code",
        },
        fix = {
          prompt = "Fix the issues in @diagnostics. Explain what was wrong and how you fixed it.",
          description = "Fix diagnostics",
        },
        test = {
          prompt = "Write comprehensive tests for @this. Cover edge cases and error conditions.",
          description = "Write tests",
        },
        optimize = {
          prompt = "Optimize @this for performance and readability. Explain the improvements.",
          description = "Optimize code",
        },
        implement = {
          prompt = "Implement @this based on the surrounding context and any comments/docstrings.",
          description = "Implement code",
        },
        refactor = {
          prompt = "Refactor @this to improve structure and maintainability. Keep functionality identical.",
          description = "Refactor code",
        },
      },
    }
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

    -- =========================================================================
    -- OPENCODE HELPERS
    -- =========================================================================
    -- OpenCode has its own toggle via require('opencode').toggle()
    -- These helpers provide additional integration points

    -- Quick prompt with buffer context
    Konductor.opencode_buffer = function()
      local opencode = require("opencode")
      opencode.prompt("Analyze @buffer and suggest improvements")
    end

    -- Quick prompt with diagnostics
    Konductor.opencode_diagnostics = function()
      local opencode = require("opencode")
      opencode.prompt("fix")  -- Uses built-in fix prompt with @diagnostics
    end

    -- Quick prompt with git diff
    Konductor.opencode_diff = function()
      local opencode = require("opencode")
      opencode.prompt("Review @diff for issues and suggest improvements")
    end

    -- Status check - is OpenCode connected?
    Konductor.opencode_status = function()
      local ok, opencode = pcall(require, "opencode")
      if not ok then
        Snacks.notifier.notify("OpenCode plugin not loaded", "error", { title = "OpenCode" })
        return
      end
      -- Try to get connection status
      local status = "OpenCode plugin loaded"
      Snacks.notifier.notify(status, "info", { title = "OpenCode", timeout = 3000 })
    end
  '';
}
