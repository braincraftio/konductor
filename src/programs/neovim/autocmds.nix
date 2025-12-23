# src/programs/neovim/autocmds.nix
# Autocommands for polish and UX excellence
#
# Every autocommand here makes the editor feel more responsive and polished
{ }:

{
  autoCmd = [
    # =========================================================================
    # VISUAL FEEDBACK
    # =========================================================================

    # Highlight on yank - brief flash when yanking text
    {
      event = "TextYankPost";
      callback.__raw = ''
        function()
          (vim.hl or vim.highlight).on_yank({ higroup = "IncSearch", timeout = 150 })
        end
      '';
    }

    # =========================================================================
    # CURSOR & POSITION
    # =========================================================================

    # Restore cursor position when opening a file
    {
      event = "BufReadPost";
      callback.__raw = ''
        function(event)
          local exclude = { "gitcommit" }
          local buf = event.buf
          if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
            return
          end
          vim.b[buf].lazyvim_last_loc = true
          local mark = vim.api.nvim_buf_get_mark(buf, '"')
          local lcount = vim.api.nvim_buf_line_count(buf)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }

    # =========================================================================
    # WINDOW MANAGEMENT
    # =========================================================================

    # Auto-resize splits when window is resized
    {
      event = "VimResized";
      callback.__raw = ''
        function()
          local current_tab = vim.fn.tabpagenr()
          vim.cmd("tabdo wincmd =")
          vim.cmd("tabnext " .. current_tab)
        end
      '';
    }

    # =========================================================================
    # FILE OPERATIONS
    # =========================================================================

    # Auto-create parent directories when saving
    {
      event = "BufWritePre";
      callback.__raw = ''
        function(event)
          if event.match:match("^%w%w+:[\\/][\\/]") then
            return
          end
          local file = vim.uv.fs_realpath(event.match) or event.match
          vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
        end
      '';
    }

    # Check for file changes when focus returns
    {
      event = [ "FocusGained" "TermClose" "TermLeave" ];
      command = "checktime";
    }

    # =========================================================================
    # BUFFER BEHAVIOR
    # =========================================================================

    # Close special buffers with 'q'
    {
      event = "FileType";
      pattern = [
        "help"
        "lspinfo"
        "notify"
        "qf"
        "query"
        "checkhealth"
        "spectre_panel"
        "neotest-output"
        "neotest-output-panel"
        "neotest-summary"
        "dbout"
        "gitsigns-blame"
      ];
      callback.__raw = ''
        function(event)
          vim.bo[event.buf].buflisted = false
          vim.schedule(function()
            vim.keymap.set("n", "q", function()
              vim.cmd("close")
              pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
            end, {
              buffer = event.buf,
              silent = true,
              desc = "Quit buffer",
            })
          end)
        end
      '';
    }

    # Make help windows open in vertical split
    {
      event = "FileType";
      pattern = [ "help" ];
      command = "wincmd L";
    }

    # =========================================================================
    # FILETYPE-SPECIFIC SETTINGS
    # =========================================================================

    # Go: tabs, 4-width
    {
      event = "FileType";
      pattern = [ "go" "gomod" "gowork" "gotmpl" ];
      callback.__raw = ''
        function()
          vim.opt_local.tabstop = 4
          vim.opt_local.shiftwidth = 4
          vim.opt_local.expandtab = false
        end
      '';
    }

    # Markdown: wrap, spell, conceal
    {
      event = "FileType";
      pattern = [ "markdown" "mdx" ];
      callback.__raw = ''
        function()
          vim.opt_local.wrap = true
          vim.opt_local.spell = true
          vim.opt_local.conceallevel = 2
        end
      '';
    }

    # Text files: wrap, spell
    {
      event = "FileType";
      pattern = [ "text" "plaintex" "typst" "gitcommit" ];
      callback.__raw = ''
        function()
          vim.opt_local.wrap = true
          vim.opt_local.spell = true
        end
      '';
    }

    # JSON/JSONC: set conceal level
    {
      event = "FileType";
      pattern = [ "json" "jsonc" "json5" ];
      callback.__raw = ''
        function()
          vim.opt_local.conceallevel = 0
        end
      '';
    }

    # Python: 4-space indent
    {
      event = "FileType";
      pattern = [ "python" ];
      callback.__raw = ''
        function()
          vim.opt_local.tabstop = 4
          vim.opt_local.shiftwidth = 4
          vim.opt_local.softtabstop = 4
        end
      '';
    }

    # Make: require tabs
    {
      event = "FileType";
      pattern = [ "make" ];
      callback.__raw = ''
        function()
          vim.opt_local.expandtab = false
        end
      '';
    }

    # =========================================================================
    # TERMINAL
    # =========================================================================

    # Terminal window options - clean buffer name, no line numbers
    # Snacks.terminal handles its own insert mode via start_insert/auto_insert options
    {
      event = "TermOpen";
      pattern = [ "*" ];
      callback.__raw = ''
        function(event)
          vim.opt_local.number = false
          vim.opt_local.relativenumber = false
          vim.opt_local.signcolumn = "no"
          -- Clean up terminal buffer name for bufferline
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(event.buf) then
              local name = vim.api.nvim_buf_get_name(event.buf)
              if name:match("^term://") then
                pcall(vim.api.nvim_buf_set_name, event.buf, "Terminal")
              end
            end
          end)
        end
      '';
    }

    # Explorer gets fixed width (left panel)
    {
      event = "FileType";
      pattern = [ "snacks_layout_box" "snacks_explorer" ];
      callback.__raw = ''
        function()
          vim.opt_local.winfixwidth = true
        end
      '';
    }

    # Claude Code gets full right side (fixed width, full height)
    {
      event = "FileType";
      pattern = [ "claude-code" ];
      callback.__raw = ''
        function()
          vim.opt_local.winfixwidth = true
          -- Ensure Claude stays full height when terminal opens
          vim.opt_local.winfixheight = false
        end
      '';
    }

    # =========================================================================
    # LSP
    # =========================================================================

    # Highlight references under cursor
    {
      event = [ "CursorHold" "CursorHoldI" ];
      callback.__raw = ''
        function()
          local clients = vim.lsp.get_clients({ bufnr = 0 })
          for _, client in ipairs(clients) do
            if client.supports_method("textDocument/documentHighlight") then
              vim.lsp.buf.document_highlight()
              return
            end
          end
        end
      '';
    }

    # Clear highlights when cursor moves
    {
      event = [ "CursorMoved" "CursorMovedI" ];
      callback.__raw = ''
        function()
          vim.lsp.buf.clear_references()
        end
      '';
    }

    # =========================================================================
    # LARGE FILES
    # =========================================================================

    # Disable features on large files (handled by snacks.bigfile, but backup)
    {
      event = "BufReadPre";
      callback.__raw = ''
        function(event)
          local file = event.match
          local size = vim.fn.getfsize(file)
          if size > 1024 * 1024 then -- 1MB
            vim.opt_local.swapfile = false
            vim.opt_local.foldmethod = "manual"
            vim.opt_local.undolevels = -1
            vim.opt_local.undoreload = 0
            vim.opt_local.list = false
            vim.b[event.buf].large_file = true
          end
        end
      '';
    }

    # =========================================================================
    # DASHBOARD BUFFER NAME - Show "Konductor" in statusline
    # =========================================================================

    {
      event = "FileType";
      pattern = [ "snacks_dashboard" ];
      callback.__raw = ''
        function(event)
          -- Set buffer name to "Konductor" for statusline display
          pcall(vim.api.nvim_buf_set_name, event.buf, "Konductor")
        end
      '';
    }

    # =========================================================================
    # EXPLORER AUTO-OPEN - IDE-like experience on wide terminals
    # =========================================================================

    # Open explorer when leaving dashboard (opening a file) on wide terminals
    # This keeps dashboard centered, then shows explorer when working
    {
      event = "BufEnter";
      callback.__raw = ''
        function(event)
          -- Skip if terminal is too narrow
          if vim.o.columns < 120 then
            return
          end

          -- Skip if already opened
          if vim.g.konductor_explorer_opened then
            return
          end

          -- Skip special buffers
          local buftype = vim.bo[event.buf].buftype
          local filetype = vim.bo[event.buf].filetype
          local bufname = vim.api.nvim_buf_get_name(event.buf)

          -- Only open for real file buffers (not dashboard, not empty)
          if buftype ~= "" or filetype == "snacks_dashboard" or filetype == "" then
            return
          end
          if bufname == "" or vim.fn.isdirectory(bufname) == 1 then
            return
          end

          -- Open explorer
          vim.g.konductor_explorer_opened = true
          vim.defer_fn(function()
            if vim.o.columns >= 120 then
              Snacks.explorer()
            end
          end, 50)
        end
      '';
    }
  ];
}
