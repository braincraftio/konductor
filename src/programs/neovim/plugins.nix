# src/programs/neovim/plugins.nix
# All plugin configurations using nixvim native options
{ pkgs, lib }:

let
  banner = import ./banner.nix { };
in

{
  plugins = {
    # =========================================================================
    # SNACKS.NVIM - Unified UI Framework
    # =========================================================================
    snacks = {
      enable = true;
      settings = {
        # Performance
        bigfile = { enabled = true; size = 1572864; }; # 1.5MB
        quickfile = { enabled = true; };

        # UI Components
        notifier = {
          enabled = true;
          timeout = 3000;
          style = "compact";
        };
        input = { enabled = true; };
        indent = {
          enabled = true;
          animate = { enabled = true; };
        };
        scroll = {
          enabled = true;
          animate = { duration = { step = 15; total = 250; }; };
        };
        statuscolumn = { enabled = true; };
        words = { enabled = true; };

        # Dashboard - Clean, professional UI
        # Single header, organized sections, no redundancy
        dashboard = {
          enabled = true;
          width = 60;

          preset = {
            # Responsive header - adapts to terminal width
            header.__raw = ''
              (function()
                local cols = vim.o.columns
                if cols >= 80 then
                  return [[
██╗  ██╗ ██████╗ ███╗   ██╗██████╗ ██╗   ██╗ ██████╗████████╗ ██████╗ ██████╗
██║ ██╔╝██╔═══██╗████╗  ██║██╔══██╗██║   ██║██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
█████╔╝ ██║   ██║██╔██╗ ██║██║  ██║██║   ██║██║        ██║   ██║   ██║██████╔╝
██╔═██╗ ██║   ██║██║╚██╗██║██║  ██║██║   ██║██║        ██║   ██║   ██║██╔══██╗
██║  ██╗╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝]]
                elseif cols >= 50 then
                  return [[
 █▄▀ █▀█ █▄ █ █▀▄ █ █ █▀▀ ▀█▀ █▀█ █▀█
 █ █ █▄█ █ ▀█ █▄▀ █▄█ █▄▄  █  █▄█ █▀▄]]
                else
                  return "KONDUCTOR"
                end
              end)()
            '';

            keys = [
              { icon = " "; key = "f"; desc = "Find File"; action.__raw = "function() Snacks.picker.files() end"; }
              { icon = " "; key = "n"; desc = "New File"; action = ":ene | startinsert"; }
              { icon = " "; key = "/"; desc = "Find Text"; action.__raw = "function() Snacks.picker.grep() end"; }
              { icon = " "; key = "r"; desc = "Recent Files"; action.__raw = "function() Snacks.picker.recent() end"; }
              { icon = " "; key = "c"; desc = "Config"; action.__raw = "function() Snacks.picker.files({cwd = vim.fn.stdpath('config')}) end"; }
              { icon = " "; key = "s"; desc = "Restore Session"; section = "session"; }
              { icon = " "; key = "e"; desc = "Explorer"; action.__raw = "function() Snacks.explorer() end"; }
              { icon = " "; key = "q"; desc = "Quit"; action = ":qa"; }
            ];
          };

          sections = [
            # Clean single-column layout - professional vertical flow
            { section = "header"; padding = 2; }
            { section = "keys"; gap = 1; padding = 1; }
            {
              icon = " ";
              title = "Git Status";
              section = "terminal";
              cmd = "git -c color.status=always status --short --branch --renames 2>/dev/null || echo 'Not a git repo'";
              height = 5;
              ttl = 300;
              indent = 2;
              padding = 1;
              enabled.__raw = "function() return Snacks.git.get_root() ~= nil end";
            }
            {
              icon = " ";
              title = "Projects";
              section = "projects";
              indent = 2;
              padding = 1;
            }
            {
              icon = " ";
              title = "Recent Files";
              section = "recent_files";
              indent = 2;
              padding = 1;
            }
          ];
        };

        # Picker (replaces Telescope) - optimized for large codebases
        picker = {
          enabled = true;
          ui_select = true; # Replace vim.ui.select with Snacks.picker
          matcher = {
            frecency = true;
            cwd_bonus = true;
          };
        };

        # Explorer (replaces Neo-tree) - with git/diagnostics
        explorer = {
          enabled = true;
          replace_netrw = true;
        };

        # Scope detection for indent/dim
        scope = { enabled = true; };

        # Terminal (replaces Toggleterm)
        terminal = { enabled = true; };

        # Git
        lazygit = { enabled = true; configure = true; };
        git = { enabled = true; };
        gitbrowse = { enabled = true; };

        # Focus
        zen = { enabled = true; };
        dim = { enabled = true; };

        # Utilities
        bufdelete = { enabled = true; };
        rename = { enabled = true; };
        scratch = { enabled = true; };
        toggle = { enabled = true; };
        debug = { enabled = true; };
        profiler = { enabled = true; };
      };
    };

    # =========================================================================
    # UI LAYER
    # =========================================================================

    bufferline = {
      enable = true;
      settings = {
        options = {
          diagnostics = "nvim_lsp";
          always_show_bufferline = true;
          separator_style = "slant";
          offsets = [{
            filetype = "snacks_layout_box";
            text = "Explorer";
            text_align = "center";
          }];
        };
      };
    };

    lualine = {
      enable = true;
      settings = {
        options = {
          theme = "catppuccin";
          globalstatus = true;
          disabled_filetypes.statusline = [ "snacks_dashboard" ];
        };
        sections = {
          lualine_a = [ "mode" ];
          lualine_b = [ "branch" "diff" "diagnostics" ];
          lualine_c = [{ __unkeyed-1 = "filename"; path = 1; }];
          lualine_x = [ "encoding" "fileformat" "filetype" ];
          lualine_y = [ "progress" ];
          lualine_z = [ "location" ];
        };
      };
    };

    which-key = {
      enable = true;
      settings = {
        preset = "modern";
        delay = 300;
        spec = [
          { __unkeyed-1 = "<leader>b"; group = "Buffer"; }
          { __unkeyed-1 = "<leader>c"; group = "Code"; }
          { __unkeyed-1 = "<leader>f"; group = "Find"; }
          { __unkeyed-1 = "<leader>g"; group = "Git"; }
          { __unkeyed-1 = "<leader>gh"; group = "Hunks"; }
          { __unkeyed-1 = "<leader>q"; group = "Session"; }
          { __unkeyed-1 = "<leader>s"; group = "Search"; }
          { __unkeyed-1 = "<leader>u"; group = "UI/Toggle"; }
          { __unkeyed-1 = "<leader>x"; group = "Diagnostics"; }
        ];
      };
    };

    mini = {
      enable = true;
      modules.icons = { };
      mockDevIcons = true;
    };

    # Explicitly disable web-devicons since we use mini.icons
    web-devicons.enable = false;

    # =========================================================================
    # EDITOR LAYER
    # =========================================================================

    treesitter = {
      enable = true;
      settings = {
        auto_install = false; # nixvim manages parsers
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = false;
        };
        indent.enable = true;
        incremental_selection = {
          enable = true;
          keymaps = {
            init_selection = "<C-space>";
            node_incremental = "<C-space>";
            scope_incremental = false;
            node_decremental = "<bs>";
          };
        };
      };
    };

    treesitter-textobjects = {
      enable = true;
      settings = {
        select = {
          enable = true;
          lookahead = true;
          keymaps = {
            "af" = "@function.outer";
            "if" = "@function.inner";
            "ac" = "@class.outer";
            "ic" = "@class.inner";
            "aa" = "@parameter.outer";
            "ia" = "@parameter.inner";
          };
        };
        move = {
          enable = true;
          goto_next_start = {
            "]f" = "@function.outer";
            "]c" = "@class.outer";
            "]a" = "@parameter.inner";
          };
          goto_previous_start = {
            "[f" = "@function.outer";
            "[c" = "@class.outer";
            "[a" = "@parameter.inner";
          };
        };
      };
    };

    persistence = {
      enable = true;
      settings = {
        dir.__raw = "vim.fn.stdpath('state') .. '/sessions/'";
      };
    };

    # =========================================================================
    # CODING LAYER
    # =========================================================================

    lsp = {
      enable = true;
      inlayHints = true;
      servers = {
        # Nix
        nil_ls = {
          enable = true;
          settings.formatting.command = [ "nixpkgs-fmt" ];
        };
        # Lua
        lua_ls = {
          enable = true;
          settings = {
            telemetry.enable = false;
            diagnostics.globals = [ "vim" "Snacks" ];
          };
        };
        # Python
        pyright.enable = true;
        # Go
        gopls = {
          enable = true;
          settings.gopls = {
            gofumpt = true;
            staticcheck = true;
          };
        };
        # Rust
        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
        };
        # TypeScript
        ts_ls.enable = true;
        # Bash
        bashls.enable = true;
        # YAML/JSON
        yamlls.enable = true;
        jsonls.enable = true;
        # Docker
        dockerls.enable = true;
        # TOML
        taplo.enable = true;
        # Markdown
        marksman.enable = true;
      };
    };

    cmp = {
      enable = true;
      autoEnableSources = true;
      settings = {
        sources = [
          { name = "nvim_lsp"; priority = 1000; }
          { name = "luasnip"; priority = 750; }
          { name = "buffer"; priority = 500; }
          { name = "path"; priority = 250; }
        ];
        mapping = {
          "<C-n>" = "cmp.mapping.select_next_item()";
          "<C-p>" = "cmp.mapping.select_prev_item()";
          "<C-b>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<C-Space>" = "cmp.mapping.complete()";
          "<C-e>" = "cmp.mapping.abort()";
          "<CR>" = "cmp.mapping.confirm({ select = true })";
        };
      };
    };

    cmp-nvim-lsp.enable = true;
    cmp-buffer.enable = true;
    cmp-path.enable = true;
    cmp-cmdline.enable = true;

    luasnip.enable = true;
    friendly-snippets.enable = true;

    conform-nvim = {
      enable = true;
      settings = {
        format_on_save = {
          timeout_ms = 3000;
          lsp_fallback = true;
        };
        formatters_by_ft = {
          lua = [ "stylua" ];
          nix = [ "nixpkgs-fmt" ];
          python = [ "black" "isort" ];
          go = [ "gofumpt" "goimports" ];
          rust = [ "rustfmt" ];
          javascript = [ "prettier" ];
          typescript = [ "prettier" ];
          json = [ "prettier" ];
          yaml = [ "prettier" ];
          markdown = [ "prettier" ];
          sh = [ "shfmt" ];
          bash = [ "shfmt" ];
          toml = [ "taplo" ];
        };
      };
    };

    nvim-autopairs = {
      enable = true;
      settings.check_ts = true;
    };

    comment.enable = true;

    todo-comments = {
      enable = true;
      settings.signs = true;
    };

    trouble = {
      enable = true;
      settings.auto_close = true;
    };

    # =========================================================================
    # GIT LAYER
    # =========================================================================

    gitsigns = {
      enable = true;
      settings = {
        signs = {
          add.text = "▎";
          change.text = "▎";
          delete.text = "";
          topdelete.text = "";
          changedelete.text = "▎";
        };
        current_line_blame = false;
      };
    };

    diffview.enable = true;

    # =========================================================================
    # AI LAYER
    # =========================================================================

    copilot-lua = {
      enable = true;
      settings = {
        suggestion = {
          enabled = true;
          auto_trigger = true;
          keymap = {
            accept = "<M-l>";
            next = "<M-]>";
            prev = "<M-[>";
            dismiss = "<C-]>";
          };
        };
        panel.enabled = true;
        filetypes = {
          yaml = true;
          markdown = true;
          gitcommit = true;
        };
      };
    };

    # =========================================================================
    # TOOLS LAYER
    # =========================================================================

    markdown-preview = {
      enable = true;
      settings = {
        auto_start = 0;
        auto_close = 1;
      };
    };
  };

  # =========================================================================
  # EXTRA PLUGINS - Only for what nixvim doesn't support natively
  # =========================================================================
  extraPlugins = with pkgs.vimPlugins; [
    # claudecode.nvim - not yet in nixvim (check regularly for addition)
    # Add only after confirming nixvim doesn't have plugins.claudecode
  ];
}
