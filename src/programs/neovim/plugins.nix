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

        # Dashboard - Professional UI with refined typography
        # Design: Clean vertical flow, elegant key styling, visual hierarchy
        dashboard = {
          enabled = true;
          width = 62;

          # Formatters for file/project sections (keys use custom text)
          formats = {
            icon.__raw = ''
              function(item)
                if item.file and (item.icon == "file" or item.icon == "directory") then
                  return Snacks.dashboard.icon(item.file, item.icon)
                end
                return { item.icon or "", width = 2, hl = "SnacksDashboardIcon" }
              end
            '';
          };

          preset = {
            header = "${banner.full}";

            # Dashboard keys - columnar layout matching Projects/Recent sections
            # Layout: | icon (3) | description centered (50) | key (3) | = 56 chars
            keys = [
              # AI-first workflow (v for vibe coding) - opens AI menu
              {
                key = "v";
                # Open the Vibe/AI which-key menu for discoverability
                action.__raw = ''
                  function()
                    -- Trigger which-key for the Vibe group
                    require('which-key').show({ keys = '<leader>v', loop = true })
                  end
                '';
                text.__raw = ''{ { "󰚩 ", hl = "SnacksDashboardIcon", width = 3 }, { "Vibe", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " v ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              # Core file operations
              {
                key = "f";
                action.__raw = "function() Snacks.picker.files() end";
                text.__raw = ''{ { "󰈞 ", hl = "SnacksDashboardIcon", width = 3 }, { "Find File", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " f ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              {
                key = "/";
                action.__raw = "function() Snacks.picker.grep() end";
                text.__raw = ''{ { "󰊄 ", hl = "SnacksDashboardIcon", width = 3 }, { "Find Text", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " / ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              {
                key = "r";
                action.__raw = "function() Snacks.picker.recent() end";
                text.__raw = ''{ { "󰋚 ", hl = "SnacksDashboardIcon", width = 3 }, { "Recent", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " r ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              # Workspace tools
              {
                key = "e";
                action.__raw = "function() Snacks.explorer() end";
                text.__raw = ''{ { "󰙅 ", hl = "SnacksDashboardIcon", width = 3 }, { "Explorer", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " e ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              {
                key = "g";
                # Open Git which-key menu for discoverability
                action.__raw = ''
                  function()
                    require('which-key').show({ keys = '<leader>g', loop = true })
                  end
                '';
                text.__raw = ''{ { "󰊢 ", hl = "SnacksDashboardIcon", width = 3 }, { "Git", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " g ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              {
                key = "t";
                # Open Terminal which-key menu for discoverability
                action.__raw = ''
                  function()
                    require('which-key').show({ keys = '<leader>t', loop = true })
                  end
                '';
                text.__raw = ''{ { "󰆍 ", hl = "SnacksDashboardIcon", width = 3 }, { "Terminal", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " t ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              # Search menu (more useful than session)
              {
                key = "s";
                # Open Search which-key menu for discoverability
                action.__raw = ''
                  function()
                    require('which-key').show({ keys = '<leader>s', loop = true })
                  end
                '';
                text.__raw = ''{ { " ", hl = "SnacksDashboardIcon", width = 3 }, { "Search", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " s ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
              {
                key = "q";
                action = ":qa";
                text.__raw = ''{ { "󰈆 ", hl = "SnacksDashboardIcon", width = 3 }, { "Quit", hl = "SnacksDashboardDesc", width = 50, align = "center" }, { " q ", hl = "SnacksDashboardKey", width = 3 } }'';
              }
            ];
          };

          sections = [
            # Header with breathing room
            { section = "header"; padding = 3; }

            # Action keys - full width columnar layout (56 chars = icon 3 + desc 50 + key 3)
            { section = "keys"; gap = 1; padding = 2; }

            # Visual separator
            {
              text.__raw = ''
                { { "────────────────────────────────────────────────────────", hl = "SnacksDashboardFooter" } }
              '';
              padding = 1;
            }

            # Git Status - compact with just filenames
            {
              icon = "󰊢 ";
              title = "Git Status";
              section = "terminal";
              # Compact git status: branch + short filenames only
              cmd = "git status -sb 2>/dev/null | head -1; git status --porcelain 2>/dev/null | cut -c4- | xargs -I{} basename {} | head -5 | sed 's/^/  /'";
              height = 6;
              ttl = 60;
              padding = 1;
              enabled.__raw = "function() return Snacks.git.get_root() ~= nil end";
            }

            # Projects - quick workspace switching
            {
              icon = " ";
              title = "Projects";
              section = "projects";
              padding = 1;
            }

            # Recent Files - lowest priority, still useful
            {
              icon = " ";
              title = "Recent Files";
              section = "recent_files";
              padding = 2;
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

        # Terminal (replaces Toggleterm) - bottom by default
        terminal = {
          enabled = true;
          win = {
            position = "bottom";
            height = 0.3;
            # Clean winbar showing cwd (not ugly term://nix/store path)
            wo.winbar = " %{b:snacks_terminal.cwd}";
          };
        };

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
          # Offset for explorer without duplicate text (explorer has its own title)
          offsets = [{
            filetype = "snacks_layout_box";
            text = "";
            separator = true;
          }];
          # Show working directory for terminals, clean names for others
          name_formatter.__raw = ''
            function(buf)
              -- Use buftype to properly detect terminal buffers (per bufferline API)
              if vim.bo[buf.bufnr].buftype == "terminal" then
                -- Prefer snacks terminal cwd if available (has rich metadata)
                local snacks_info = vim.b[buf.bufnr].snacks_terminal
                if snacks_info and snacks_info.cwd then
                  local cwd = snacks_info.cwd:gsub(vim.env.HOME, "~")
                  return " " .. cwd
                end
                -- Fallback: extract cwd from term://path//pid:shell format
                -- Pattern: anchor on //digits (PID) to find the path portion
                local term_path = vim.api.nvim_buf_get_name(buf.bufnr)
                local dir = term_path:match("^term://(.+)//%d")
                if dir then
                  return " " .. dir:gsub(vim.env.HOME, "~")
                end
                return " term"
              end
              -- Regular files: use default basename
              return buf.name
            end
          '';
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
          # Custom filename with location-aware context
          lualine_c = [{
            __unkeyed-1.__raw = ''
              function()
                local ft = vim.bo.filetype
                -- Dashboard: brand name
                if ft == "snacks_dashboard" then
                  return "󰣇 Konductor"
                -- Explorer/layout: hide (has own title)
                elseif ft == "snacks_layout_box" or ft == "snacks_explorer" then
                  return ""
                -- Terminal: show cwd for "where am I" context
                elseif ft == "snacks_terminal" or vim.bo.buftype == "terminal" then
                  local snacks_info = vim.b.snacks_terminal
                  if snacks_info and snacks_info.cwd then
                    local cwd = snacks_info.cwd:gsub(vim.env.HOME, "~")
                    return " " .. cwd
                  end
                  return " Terminal"
                -- Claude Code: show context
                elseif ft == "claude-code" then
                  return "󰚩 Claude"
                else
                  -- Files: relative path for location context
                  return vim.fn.expand("%:~:.")
                end
              end
            '';
          }];
          lualine_x = [ "filetype" ];
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
          # Primary workflow groups
          { __unkeyed-1 = "<leader>v"; group = "Vibe"; icon = "󰚩"; }
          { __unkeyed-1 = "<leader>l"; group = "LSP"; icon = ""; }
          { __unkeyed-1 = "<leader>f"; group = "Find"; icon = ""; }
          { __unkeyed-1 = "<leader>s"; group = "Search"; icon = ""; }
          { __unkeyed-1 = "<leader>b"; group = "Buffer"; icon = "󰓩"; }
          { __unkeyed-1 = "<leader>g"; group = "Git"; icon = ""; }
          { __unkeyed-1 = "<leader>gh"; group = "Hunks"; icon = ""; }
          { __unkeyed-1 = "<leader>t"; group = "Terminal"; icon = ""; }
          { __unkeyed-1 = "<leader>w"; group = "Window"; icon = ""; }
          { __unkeyed-1 = "<leader>x"; group = "Diagnostics"; icon = ""; }
          { __unkeyed-1 = "<leader>m"; group = "Markdown"; icon = ""; }
          { __unkeyed-1 = "<leader>r"; group = "REST"; icon = ""; }
          { __unkeyed-1 = "<leader>q"; group = "Session/Quit"; icon = "󰈆"; }
          { __unkeyed-1 = "<leader>u"; group = "UI Toggle"; icon = ""; }

          # Bracket motions
          { __unkeyed-1 = "]"; group = "Next"; }
          { __unkeyed-1 = "["; group = "Previous"; }

          # g prefix
          { __unkeyed-1 = "g"; group = "Goto/Actions"; }
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
      nixGrammars = true;
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
        c
        cpp
        css
        dockerfile
        go
        gomod
        gosum
        html
        http # Required for rest.nvim
        javascript
        json
        jsonc
        lua
        luadoc
        make
        markdown
        markdown_inline
        nix
        python
        query
        regex
        rust
        toml
        tsx
        typescript
        vim
        vimdoc
        xml
        yaml
      ];
      settings = {
        auto_install = false; # nixvim manages parsers
        sync_install = false;
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
            scope_incremental = "<C-s>";
            node_decremental = "<C-backspace>";
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

    # Claude Code - Official Anthropic Claude integration
    claude-code = {
      enable = true;
      settings = {
        # Window settings - vertical split on right side
        window = {
          split_ratio = 0.4;
          position = "vertical";  # Creates vsplit (respects splitright)
          enter_insert = true;
          hide_numbers = true;
          hide_signcolumn = true;
        };
        # Auto-refresh for file changes
        refresh = {
          enable = true;
          updatetime = 100;
          timer_interval = 1000;
          show_notifications = true;
        };
        # Use git root as working directory
        git.use_git_root = true;
        # Command configuration
        command = "claude";
        command_variants = {
          continue = "--continue";
          resume = "--resume";
          verbose = "--verbose";
        };
        # Keymaps handled in keymaps.nix, disable defaults
        keymaps = {
          toggle = {
            normal = false;
            terminal = false;
          };
          window_navigation = true;
          scrolling = true;
        };
      };
    };

    copilot-lua = {
      enable = true;
      settings = {
        # Disable suggestion/panel - using copilot-cmp for nvim-cmp integration instead
        # This provides unified completion UX through the cmp popup
        suggestion.enabled = false;
        panel.enabled = false;
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

    # HTTP client for .http files
    rest = {
      enable = true;
      settings = {
        client = "curl";
        custom_dynamic_variables = { };
        request = {
          skip_ssl_verification = false;
          hooks = {
            encode_url = true;
          };
        };
        response = {
          hooks = {
            decode_url = true;
            format = true;
          };
        };
      };
    };

    # Copilot completion source
    copilot-cmp.enable = true;
  };

  # =========================================================================
  # EXTRA PLUGINS - Only for what nixvim doesn't support natively
  # =========================================================================
  extraPlugins =
    let
      buildVimPlugin = pkgs.vimUtils.buildVimPlugin;
    in
    [
      # render-markdown.nvim - live in-editor markdown rendering (normal mode)
      ((buildVimPlugin {
        name = "render-markdown.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "MeanderingProgrammer";
          repo = "render-markdown.nvim";
          rev = "6e0e8902dac70fecbdd8ce557d142062a621ec38";
          sha256 = "sha256-0DwPuzqR+7R4lJFQ9f2xN26YhdQKg85Hw6+bPvloZoc=";
        };
      }).overrideAttrs (old: {
        doCheck = false;
        postInstall = (old.postInstall or "") + ''
          mkdir -p $out/plugin
          cat > $out/plugin/render-markdown-setup.lua << 'EOF'
          -- Auto-initialize render-markdown on plugin load
          local ok, render_markdown = pcall(require, "render-markdown")
          if ok then
            render_markdown.setup({
              enabled = true,
              preset = 'obsidian',
              render_modes = { 'n', 'c', 't' },
              anti_conceal = { enabled = true },
              heading = { enabled = true },
              code = { enabled = true, style = 'full' },
            })
          end
          EOF
        '';
      }))
    ];

  # =========================================================================
  # TREESITTER INJECTION QUERIES - mise/usage syntax highlighting
  # =========================================================================
  extraFiles = {
    # TOML injections for mise run commands
    "after/queries/toml/injections.scm".text = ''
      ; extends

      (pair
        (bare_key) @key (#eq? @key "run")
        (string) @injection.content @injection.language

        (#is-mise?)
        (#match? @injection.language "^['\"]{3}\n*#!(/\\w+)+/env\\s+\\w+")
        (#gsub! @injection.language "^.*#!/.*/env%s+([^%s]+).*" "%1")
        (#offset! @injection.content 0 3 0 -3)
      )

      (pair
        (bare_key) @key (#eq? @key "run")
        (string) @injection.content @injection.language

        (#is-mise?)
        (#match? @injection.language "^['\"]{3}\n*#!(/\\w+)+\s*\n")
        (#gsub! @injection.language "^.*#!/.*/([^/%s]+).*" "%1")
        (#offset! @injection.content 0 3 0 -3)
      )

      (pair
        (bare_key) @key (#eq? @key "run")
        (string) @injection.content

        (#is-mise?)
        (#match? @injection.content "^['\"]{3}\n*.*")
        (#not-match? @injection.content "^['\"]{3}\n*#!")
        (#offset! @injection.content 0 3 0 -3)
        (#set! injection.language "bash")
      )

      (pair
        (bare_key) @key (#eq? @key "run")
        (string) @injection.content

        (#is-mise?)
        (#not-match? @injection.content "^['\"]{3}")
        (#offset! @injection.content 0 1 0 -1)
        (#set! injection.language "bash")
      )
    '';

    # Bash injections for mise and usage comments
    "after/queries/bash/injections.scm".text = ''
      ; extends

      ((comment) @injection.content
        (#lua-match? @injection.content "^#MISE ")
        (#offset! @injection.content 0 6 0 1)
        (#set! injection.language "toml"))

      ((comment) @injection.content
        (#lua-match? @injection.content "^#USAGE ")
        (#offset! @injection.content 0 7 0 1)
        (#set! injection.combined)
        (#set! injection.language "kdl"))
    '';
  };
}
