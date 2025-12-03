# src/programs/neovim/default.nix
# Neovim configuration using nixvim

{ pkgs, lib, inputs }:

let
  # Import nixvim's package builder
  nixvimPkgs = inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Get bash configuration for terminal shell
  bashConfig = import ../shell/bash.nix { inherit pkgs lib; };

  # Define nixvim configuration
  nixvimConfig = nixvimPkgs.makeNixvim {
    # Early plugin initialization (runs before plugins load)
    # This ensures globals are set for healthchecks
    extraConfigLuaPre = ''
      -- Pre-initialize globals that plugins expect
      -- This runs before plugin loading, ensuring healthchecks work
    '';

    # Use catppuccin colorscheme matching tmux
    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "macchiato";
    };

    # Essential options
    opts = {
      # Line numbers
      number = true;
      relativenumber = true;
      signcolumn = "yes";

      # Indentation
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;

      # Search
      ignorecase = true;
      smartcase = true;

      # UI
      termguicolors = true;
      cursorline = true;

      # Performance
      updatetime = 250;
      timeoutlen = 300;

      # Shada (persistent state) - use empty to avoid host file issues
      # Set to NONE to disable, or keep default for persistence
      shada = "'100,<50,s10,h";

      # Shell settings - use Nix bash (5.x), not system bash
      shell = "${pkgs.bash}/bin/bash";
      shellcmdflag = "-c";
      shellquote = "";
      shellxquote = "";
      shellpipe = "2>&1| tee";
      shellredir = ">%s 2>&1";

      # Terminal behavior
      splitbelow = true;
      splitright = true;
      scrollback = 10000;
      title = true;
      titlestring = "nvim - %f";
      mouse = "a";
    };

    # Leader key and globals
    globals = {
      mapleader = " ";
      maplocalleader = " ";
      nvim_terminal = 1;
      # Disable unused providers to avoid healthcheck errors
      loaded_ruby_provider = 0;
      loaded_perl_provider = 0;
      # Suppress vim.validate deprecation warnings (upstream plugin issue)
      deprecation_warnings = false;
    };

    # Essential keymaps
    keymaps = [
      # Save/Quit
      { mode = "n"; key = "<leader>w"; action = "<cmd>w<cr>"; options.desc = "Save"; }
      { mode = "n"; key = "<leader>q"; action = "<cmd>q<cr>"; options.desc = "Quit"; }
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<cr>"; }
      { mode = "i"; key = "jk"; action = "<Esc>"; options.desc = "Exit insert mode"; }

      # LSP keymaps
      { mode = "n"; key = "<leader>lf"; action = "<cmd>lua vim.lsp.buf.format()<cr>"; options.desc = "Format buffer"; }
      { mode = "n"; key = "<leader>li"; action = "<cmd>LspInfo<cr>"; options.desc = "LSP Info"; }
      { mode = "n"; key = "<leader>lr"; action = "<cmd>LspRestart<cr>"; options.desc = "LSP Restart"; }

      # Terminal keymaps
      { mode = "n"; key = "<leader>tt"; action = "<cmd>ToggleTerm<cr>"; options.desc = "Toggle terminal"; }
      { mode = "n"; key = "<leader>tf"; action = "<cmd>ToggleTerm direction=float<cr>"; options.desc = "Float terminal"; }
      { mode = "n"; key = "<leader>th"; action = "<cmd>ToggleTerm direction=horizontal<cr>"; options.desc = "Horizontal terminal"; }
      { mode = "n"; key = "<leader>tv"; action = "<cmd>ToggleTerm direction=vertical<cr>"; options.desc = "Vertical terminal"; }

      # Terminal mode navigation
      { mode = "t"; key = "<C-h>"; action = "<cmd>wincmd h<cr>"; options.desc = "Move to left window"; }
      { mode = "t"; key = "<C-j>"; action = "<cmd>wincmd j<cr>"; options.desc = "Move to below window"; }
      { mode = "t"; key = "<C-k>"; action = "<cmd>wincmd k<cr>"; options.desc = "Move to above window"; }
      { mode = "t"; key = "<C-l>"; action = "<cmd>wincmd l<cr>"; options.desc = "Move to right window"; }
      { mode = "t"; key = "<Esc><Esc>"; action = "<C-\\><C-n>"; options.desc = "Exit terminal mode"; }

      # Git keymaps
      { mode = "n"; key = "<leader>gs"; action = "<cmd>Git<cr>"; options.desc = "Git status"; }
      { mode = "n"; key = "<leader>gc"; action = "<cmd>Git commit<cr>"; options.desc = "Git commit"; }
      { mode = "n"; key = "<leader>gp"; action = "<cmd>Git push<cr>"; options.desc = "Git push"; }
      { mode = "n"; key = "<leader>gd"; action = "<cmd>DiffviewOpen<cr>"; options.desc = "Git diff"; }
      { mode = "n"; key = "<leader>gh"; action = "<cmd>DiffviewFileHistory<cr>"; options.desc = "Git history"; }

      # HTTP client keymaps
      { mode = "n"; key = "<leader>rr"; action = "<Plug>RestNvim"; options.desc = "Run HTTP request"; }
      { mode = "n"; key = "<leader>rp"; action = "<Plug>RestNvimPreview"; options.desc = "Preview HTTP request"; }
      { mode = "n"; key = "<leader>rl"; action = "<Plug>RestNvimLast"; options.desc = "Rerun last HTTP request"; }

      # Markdown keymaps (render-markdown.nvim)
      { mode = "n"; key = "<leader>mt"; action = "<cmd>RenderMarkdown toggle<cr>"; options.desc = "Toggle markdown render"; }

      # Comment keymaps - remap to avoid gc/gcc overlap warning
      # Use <leader>/ for line comment (replaces gcc)
      { mode = "n"; key = "<leader>/"; action = "gcc"; options.desc = "Toggle comment line"; options.remap = true; }
      { mode = "v"; key = "<leader>/"; action = "gc"; options.desc = "Toggle comment selection"; options.remap = true; }
      { mode = "n"; key = "<leader>mp"; action = "<cmd>RenderMarkdown preview<cr>"; options.desc = "Markdown preview (side)"; }
      { mode = "n"; key = "<leader>me"; action = "<cmd>RenderMarkdown expand<cr>"; options.desc = "Expand anti-conceal"; }
      { mode = "n"; key = "<leader>mc"; action = "<cmd>RenderMarkdown contract<cr>"; options.desc = "Contract anti-conceal"; }

      # Browse.nvim keymaps
      { mode = "n"; key = "<leader>bb"; action = "<cmd>Browse<cr>"; options.desc = "Browse menu"; }
      { mode = "n"; key = "<leader>bi"; action = "<cmd>Browse input<cr>"; options.desc = "Browse input search"; }
      { mode = "n"; key = "<leader>bm"; action = "<cmd>Browse mdn<cr>"; options.desc = "Browse MDN"; }
      { mode = "n"; key = "<leader>bd"; action = "<cmd>Browse devdocs<cr>"; options.desc = "Browse DevDocs"; }
      { mode = "n"; key = "<leader>bf"; action = "<cmd>Browse devdocs_ft<cr>"; options.desc = "Browse DevDocs (filetype)"; }
      { mode = "n"; key = "<leader>bk"; action = "<cmd>Browse bookmarks<cr>"; options.desc = "Browse bookmarks"; }
      { mode = "v"; key = "<leader>bb"; action = "<cmd>Browse<cr>"; options.desc = "Browse selection"; }

      # ClaudeCode keymaps (AI integration)
      { mode = "n"; key = "<leader>ac"; action = "<cmd>ClaudeCode<cr>"; options.desc = "Toggle Claude"; }
      { mode = "n"; key = "<leader>af"; action = "<cmd>ClaudeCodeFocus<cr>"; options.desc = "Focus Claude"; }
      { mode = "n"; key = "<leader>ar"; action = "<cmd>ClaudeCode --resume<cr>"; options.desc = "Resume Claude"; }
      { mode = "n"; key = "<leader>aC"; action = "<cmd>ClaudeCode --continue<cr>"; options.desc = "Continue Claude"; }
      { mode = "n"; key = "<leader>am"; action = "<cmd>ClaudeCodeSelectModel<cr>"; options.desc = "Select Claude model"; }
      { mode = "n"; key = "<leader>ab"; action = "<cmd>ClaudeCodeAdd %<cr>"; options.desc = "Add current buffer"; }
      { mode = "v"; key = "<leader>as"; action = "<cmd>ClaudeCodeSend<cr>"; options.desc = "Send to Claude"; }
      { mode = "n"; key = "<leader>aa"; action = "<cmd>ClaudeCodeDiffAccept<cr>"; options.desc = "Accept diff"; }
      { mode = "n"; key = "<leader>ad"; action = "<cmd>ClaudeCodeDiffDeny<cr>"; options.desc = "Deny diff"; }

      # Copilot inline keymaps (copilot-lua plugin)
      { mode = "n"; key = "<leader>aP"; action = "<cmd>Copilot panel<cr>"; options.desc = "Copilot suggestions panel"; }
      { mode = "n"; key = "<leader>ae"; action = "<cmd>Copilot enable<cr>"; options.desc = "Copilot enable"; }
      { mode = "n"; key = "<leader>aX"; action = "<cmd>Copilot disable<cr>"; options.desc = "Copilot disable"; }
      { mode = "n"; key = "<leader>at"; action = "<cmd>Copilot status<cr>"; options.desc = "Copilot status"; }
      # Note: <leader>ap (Copilot CLI) and <leader>ax (Codex CLI) are defined in extraConfigLua as toggleable terminals

      # File tree keymaps
      { mode = "n"; key = "<leader>ft"; action = "<cmd>Neotree toggle<cr>"; options.desc = "Toggle file tree"; }
      { mode = "n"; key = "<leader>fe"; action = "<cmd>Neotree focus<cr>"; options.desc = "Focus file tree"; }
      { mode = "n"; key = "<leader>fF"; action = "<cmd>Neotree reveal<cr>"; options.desc = "Reveal in file tree"; }
    ];

    # Terminal autocommands
    autoCmd = [
      {
        event = "TermOpen";
        pattern = "*";
        callback.__raw = ''
          function()
            vim.opt_local.number = false
            vim.opt_local.relativenumber = false
            vim.opt_local.signcolumn = "no"
            vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], { buffer = true, desc = "Exit terminal mode" })
          end
        '';
      }
      {
        event = "TermClose";
        pattern = "*";
        callback.__raw = ''
          function()
            vim.cmd("bdelete!")
          end
        '';
      }
      # Set formatprg for rest-nvim response body formatting
      {
        event = "FileType";
        pattern = "json";
        callback.__raw = ''
          function()
            vim.opt_local.formatprg = "jq ."
          end
        '';
      }
      {
        event = "FileType";
        pattern = "html";
        callback.__raw = ''
          function()
            vim.opt_local.formatprg = "prettier --parser html"
          end
        '';
      }
    ];

    # Core plugins
    plugins = {
      # File icons
      web-devicons.enable = true;

      # Status line
      lualine = {
        enable = true;
        settings = {
          options = {
            theme = "catppuccin";
            component_separators = { left = ""; right = ""; };
            section_separators = { left = ""; right = ""; };
          };
          sections = {
            lualine_x = [
              "copilot"
              "encoding"
              "fileformat"
              "filetype"
            ];
          };
        };
      };

      # Fuzzy finder
      telescope = {
        enable = true;
        settings = {
          defaults = {
            hidden = true;
            file_ignore_patterns = [
              "^%.git/"
              "__pycache__/"
              "^node_modules/"
              "^target/"
              "^result"
            ];
            layout_strategy = "horizontal";
            layout_config = {
              horizontal = {
                prompt_position = "top";
                preview_width = 0.55;
              };
              width = 0.87;
              height = 0.80;
            };
            sorting_strategy = "ascending";
            prompt_prefix = "   ";
            selection_caret = "  ";
            entry_prefix = "  ";
            path_display = [ "truncate" ];
          };
          pickers = {
            find_files = {
              hidden = true;
              no_ignore = false;
              follow = true;
            };
            live_grep = {
              additional_args = [ "--hidden" "--glob" "!.git/*" ];
            };
            buffers = {
              show_all_buffers = true;
              sort_lastused = true;
            };
          };
        };
        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fr" = "oldfiles";
          "<leader>fc" = "current_buffer_fuzzy_find";
          "<leader>fd" = "diagnostics";
          "<leader>fs" = "lsp_document_symbols";
          "<leader>fw" = "grep_string";
        };
      };

      # Syntax highlighting
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      # File tree with full optional dependencies
      neo-tree = {
        enable = true;
        settings = {
          enable_diagnostics = true;
          enable_git_status = true;
          close_if_last_window = true;
          popup_border_style = "rounded";
          sort_case_insensitive = true;
          window = {
            position = "left";
            width = 35;
            mappings = {
              "<space>" = "none";
              "h" = "close_node";
              "l" = "open";
              "H" = "toggle_hidden";
              "." = "set_root";
              "/" = "fuzzy_finder";
            };
          };
          default_component_configs = {
            indent = {
              with_expanders = true;
              expander_collapsed = "";
              expander_expanded = "";
              expander_highlight = "NeoTreeExpander";
            };
            git_status = {
              symbols = {
                added = "✚";
                modified = "";
                deleted = "✖";
                renamed = "󰁕";
                untracked = "";
                ignored = "";
                unstaged = "󰄱";
                staged = "";
                conflict = "";
              };
            };
          };
          filesystem = {
            filtered_items = {
              visible = true;
              show_hidden_count = true;
              hide_dotfiles = false;
              hide_gitignored = false;
              hide_by_name = [
                ".git"
                "__pycache__"
                "node_modules"
                ".DS_Store"
                "result"
              ];
              never_show = [
                ".DS_Store"
                "thumbs.db"
              ];
            };
            follow_current_file = {
              enabled = true;
              leave_dirs_open = false;
            };
            use_libuv_file_watcher = true;
            group_empty_dirs = true;
            hijack_netrw_behavior = "open_current";
          };
        };
      };

      # Mini icons for icon support
      mini = {
        enable = true;
        modules = {
          icons = {
            style = "glyph";
          };
        };
      };

      # LSP configuration
      lsp = {
        enable = true;
        keymaps = {
          silent = true;
          diagnostic = {
            "<leader>j" = "goto_next";
            "<leader>k" = "goto_prev";
          };
          lspBuf = {
            gd = "definition";
            gr = "references";
            gI = "implementation";
            gy = "type_definition";
            K = "hover";
            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
          };
        };
        servers = {
          # Nix
          nil_ls = {
            enable = true;
            settings.formatting.command = [ "nixpkgs-fmt" ];
          };
          # Lua
          lua_ls = {
            enable = true;
            settings.telemetry.enable = false;
          };
          # Bash
          bashls.enable = true;
          # YAML
          yamlls.enable = true;
          # Markdown
          marksman.enable = true;
          # JSON
          jsonls.enable = true;
          # Python
          pyright = {
            enable = true;
            settings.python.analysis.typeCheckingMode = "basic";
          };
          # Go
          gopls.enable = true;
          # Rust
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
          };
          # TypeScript/JavaScript
          ts_ls.enable = true;
        };
      };

      # Completion
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<C-e>" = "cmp.mapping.close()";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
            "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
          };
          sources = [
            { name = "copilot"; group_index = 2; } # AI suggestions
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "path"; }
            { name = "buffer"; }
          ];
        };
      };

      # Snippets
      luasnip = {
        enable = true;
        fromVscode = [{ }];
      };

      # Code formatting
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            nix = [ "nixpkgs_fmt" ];
            python = [ "black" "isort" ];
            rust = [ "rustfmt" ];
            go = [ "gofmt" "goimports" ];
            javascript = [ "prettier" ];
            typescript = [ "prettier" ];
            markdown = [ "prettier" ];
            yaml = [ "prettier" ];
            json = [ "prettier" ];
            bash = [ "shfmt" ];
            sh = [ "shfmt" ];
          };
          format_on_save = {
            lsp_fallback = true;
            timeout_ms = 500;
          };
        };
      };

      # Terminal integration
      toggleterm = {
        enable = true;
        settings = {
          size.__raw = ''
            function(term)
              if term.direction == "horizontal" then
                return 15
              elseif term.direction == "vertical" then
                return vim.o.columns * 0.4
              else
                return 20
              end
            end
          '';
          open_mapping = "[[<C-\\>]]";
          hide_numbers = true;
          shade_terminals = true;
          shading_factor = 2;
          start_in_insert = true;
          insert_mappings = true;
          terminal_mappings = true;
          persist_size = true;
          persist_mode = true;
          direction = "float";
          float_opts = {
            border = "curved";
            width.__raw = "function() return math.floor(vim.o.columns * 0.85) end";
            height.__raw = "function() return math.floor(vim.o.lines * 0.85) end";
            winblend = 0;
            highlights = {
              border = "Normal";
              background = "Normal";
            };
          };
          shell = "${bashConfig.nvimTerminalBashWrapper}";
          env = {
            TERM = "xterm-256color";
            NVIM.__raw = "vim.v.servername";
            NVIM_TERMINAL = "1";
            TERM_PROGRAM = "nvim";
            PATH.__raw = "vim.env.PATH";
            HOME.__raw = "vim.env.HOME";
            USER.__raw = "vim.env.USER";
          };
          on_open.__raw = ''
            function(term)
              vim.cmd("startinsert!")
              vim.opt_local.number = false
              vim.opt_local.relativenumber = false
              vim.opt_local.signcolumn = "no"
            end
          '';
          on_close.__raw = "function(term) end";
          highlights = {
            Normal = { link = "Normal"; };
            NormalFloat = { link = "NormalFloat"; };
            FloatBorder = { link = "FloatBorder"; };
          };
          auto_scroll = true;
          close_on_exit = true;
        };
      };

      # Git integration
      gitsigns = {
        enable = true;
        lazyLoad = {
          enable = true;
          settings.event = [ "BufReadPre" "BufNewFile" ];
        };
        settings = {
          current_line_blame = true;
          current_line_blame_opts = {
            virt_text = true;
            virt_text_pos = "eol";
          };
          signs = {
            add = { text = "|"; };
            change = { text = "|"; };
            delete = { text = "_"; };
            topdelete = { text = "-"; };
            changedelete = { text = "~"; };
            untracked = { text = ":"; };
          };
        };
      };

      fugitive.enable = true;
      diffview = {
        enable = true;
        settings = {
          enhanced_diff_hl = true;
          use_icons = true;
          view = {
            default = { layout = "diff2_horizontal"; };
            merge_tool = { layout = "diff3_horizontal"; };
          };
        };
      };

      # HTTP client (rest.nvim)
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
          highlight = {
            enabled = true;
            timeout = 150;
          };
          keybinds = { };
        };
      };

      # Command discovery
      which-key = {
        enable = true;
        settings = {
          delay = 500;
          icons = {
            breadcrumb = ">>";
            separator = "->";
            group = "+";
          };
          win = {
            border = "rounded";
            padding = [ 2 2 ];
          };
          # Ignore intentional overlaps (gc is operator, gcc is line-specific)
          notify = false;
        };
      };

      # GitHub Copilot (Lua version for better cmp integration)
      copilot-lua = {
        enable = true;
        settings = {
          suggestion.enabled = false; # Use cmp instead
          panel.enabled = false; # Use cmp instead
          filetypes = {
            markdown = true;
            help = false;
          };
        };
      };
      copilot-cmp.enable = true; # Copilot as cmp source

      # Lazy loading
      lz-n = {
        enable = true;
        plugins = [
          { __unkeyed-1 = "vim-fugitive"; cmd = [ "Git" "G" ]; }
          # Note: diffview removed from lazy loading - needs early init for healthcheck
          { __unkeyed-1 = "rest.nvim"; ft = [ "http" ]; }
        ];
      };
    };

    # Extra plugins not yet in nixpkgs
    extraPlugins = with pkgs.vimUtils; [
      # Claude Code integration
      (buildVimPlugin {
        name = "claudecode.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "coder";
          repo = "claudecode.nvim";
          rev = "1552086ebcce9f4a2ea3b9793018a884d6b60169";
          sha256 = "sha256-XYmf1RQ2bVK6spINZW4rg6OQQ5CWWcR0Tw4QX8ZDjgs=";
        };
      })

      # Snacks.nvim - neo-tree optional dependency
      # Note: Setup is in extraConfigLua, healthcheck may show error until first use
      ((buildVimPlugin {
        name = "snacks.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "folke";
          repo = "snacks.nvim";
          rev = "fe7cfe9800a182274d0f868a74b7263b8c0c020b";
          sha256 = "sha256-vRedYg29QGPGW0hOX9qbRSIImh1d/SoDZHImDF2oqKM=";
        };
      }).overrideAttrs (old: {
        doCheck = false;
        # Add auto-setup on plugin load
        postInstall = (old.postInstall or "") + ''
          mkdir -p $out/plugin
          cat > $out/plugin/snacks-setup.lua << 'EOF'
          -- Auto-initialize Snacks on plugin load
          local ok, snacks = pcall(require, "snacks")
          if ok then
            _G.Snacks = snacks
            snacks.setup({
              bigfile = { enabled = true },
              indent = { enabled = true },
              input = { enabled = true },
              notifier = { enabled = true },
              quickfile = { enabled = true },
              scroll = { enabled = true },
              statuscolumn = { enabled = true },
              words = { enabled = true },
              image = { enabled = true },
              -- Explicitly disable features we don't use to avoid healthcheck issues
              dashboard = { enabled = false },
              explorer = { enabled = false },
              picker = { enabled = false },
            })
            -- Set vim.ui.input to use Snacks
            vim.ui.input = Snacks.input
          end
          EOF
        '';
      }))

      # Image.nvim - neo-tree optional for image preview
      ((buildVimPlugin {
        name = "image.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "3rd";
          repo = "image.nvim";
          rev = "446a8a5cc7a3eae3185ee0c697732c32a5547a0b";
          sha256 = "sha256-EaDeY8aP41xHTw5epqYjaBqPYs6Z2DABzSaVOnG6D6I=";
        };
      }).overrideAttrs (_old: { doCheck = false; }))

      # LSP file operations - neo-tree optional
      ((buildVimPlugin {
        name = "nvim-lsp-file-operations";
        src = pkgs.fetchFromGitHub {
          owner = "antosha417";
          repo = "nvim-lsp-file-operations";
          rev = "9744b738183a5adca0f916527922078a965515ed";
          sha256 = "sha256-c56N0E6NA3g58IRgnTtvGmpJ+uZemdmoIsQmPcvbrHY=";
        };
      }).overrideAttrs (_old: { doCheck = false; }))

      # Window picker for neo-tree
      (buildVimPlugin {
        name = "nvim-window-picker";
        src = pkgs.fetchFromGitHub {
          owner = "s1n7ax";
          repo = "nvim-window-picker";
          rev = "6382540b2ae5de6c793d4aa2e3fe6dbb518505ec";
          sha256 = "sha256-ZavIPpQXLSRpJXJVJZp3N6QWHoTKRvVrFAw7jekNmX4=";
        };
      })

      # Browse.nvim - unified web browsing
      ((buildVimPlugin {
        name = "browse.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "lalitmee";
          repo = "browse.nvim";
          rev = "31c19629212b66801a467cdf8127d8639e5ebb7e";
          sha256 = "sha256-lecDroWvWTz1QOFLlq4IwDE+t0oImbMTN8Fzy+yRj9M=";
        };
      }).overrideAttrs (_old: { doCheck = false; }))

      # Render-markdown.nvim - beautiful markdown rendering
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
        # Add auto-setup on plugin load
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

    # Performance optimizations
    performance = {
      byteCompileLua = {
        enable = true;
        initLua = true;
        configs = true;
        plugins = true;
        nvimRuntime = false;
      };
      combinePlugins.enable = false;
    };

    # Treesitter injection queries for mise integration
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

    # Additional Lua configuration
    extraConfigLua = ''
      -- Mise Integration (treesitter syntax highlighting for mise config files)
      -- Note: mise shims NOT added to PATH - Nix provides all tools directly

      require("vim.treesitter.query").add_predicate("is-mise?", function(_, _, bufnr, _)
        local filepath = vim.api.nvim_buf_get_name(tonumber(bufnr) or 0)
        local filename = vim.fn.fnamemodify(filepath, ":t")
        return string.match(filename, ".*mise.*%.toml$") ~= nil
      end, { force = true, all = false })

      -- Note: Snacks.nvim is auto-initialized via plugin/snacks-setup.lua

      -- Image.nvim Configuration
      local image_ok, image = pcall(require, "image")
      if image_ok then
        image.setup({
          backend = "kitty",
          integrations = {
            markdown = { enabled = true },
          },
          max_width = 100,
          max_height = 12,
        })
      end

      -- LSP file operations Configuration
      local lsp_file_ops_ok, lsp_file_operations = pcall(require, "lsp-file-operations")
      if lsp_file_ops_ok then
        lsp_file_operations.setup()
      end

      -- Window picker Configuration
      local window_picker_ok, window_picker = pcall(require, "window-picker")
      if window_picker_ok then
        window_picker.setup({
          hint = "floating-big-letter",
          selection_chars = "FJDKSLA;CMRUEIWOQP",
          filter_rules = {
            include_current_win = false,
            autoselect_one = true,
            bo = {
              filetype = { "neo-tree", "neo-tree-popup", "notify" },
              buftype = { "terminal", "quickfix" },
            },
          },
        })
      end

      -- ClaudeCode.nvim Configuration
      local claudecode_ok, claudecode = pcall(require, "claudecode")
      if claudecode_ok then
        claudecode.setup({
          auto_start = true,
          log_level = "info",
          track_selection = true,
          terminal = {
            split_side = "right",
            split_width_percentage = 0.40,
            provider = "snacks",
            auto_close = true,
          },
          diff_opts = {
            auto_close_on_accept = true,
            vertical_split = true,
            open_in_current_tab = true,
            keep_terminal_focus = false,
          },
        })
      end

      -- Note: Render-markdown.nvim is auto-initialized via plugin/render-markdown-setup.lua

      -- Browse.nvim Configuration
      local browse_ok, browse = pcall(require, "browse")
      if browse_ok then
        browse.setup({
          provider = "duckduckgo",
        })
      end

      -- LazyGit Integration
      local Terminal = require('toggleterm.terminal').Terminal
      local lazygit = Terminal:new({
        cmd = "lazygit",
        hidden = true,
        direction = "float",
        float_opts = { border = "curved" },
      })
      function _lazygit_toggle()
        lazygit:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>tg", "<cmd>lua _lazygit_toggle()<CR>", {noremap = true, silent = true, desc = "LazyGit"})

      -- Copilot CLI Integration (vertical split on right, like Claude)
      local copilot_cli = Terminal:new({
        cmd = "copilot",
        hidden = true,
        direction = "vertical",
        dir = vim.fn.getcwd(),
        on_open = function(term)
          vim.cmd("startinsert!")
        end,
      })
      function _copilot_cli_toggle()
        copilot_cli:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>ap", "<cmd>lua _copilot_cli_toggle()<CR>", {noremap = true, silent = true, desc = "Copilot CLI"})

      -- Codex CLI Integration (vertical split on right, like Claude)
      local codex_cli = Terminal:new({
        cmd = "codex",
        hidden = true,
        direction = "vertical",
        dir = vim.fn.getcwd(),
        on_open = function(term)
          vim.cmd("startinsert!")
        end,
      })
      function _codex_cli_toggle()
        codex_cli:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>ax", "<cmd>lua _codex_cli_toggle()<CR>", {noremap = true, silent = true, desc = "Codex CLI"})
    '';
  };

in
{
  # Export neovim package built from nixvim config
  packages = [ nixvimConfig ];

  # No shell hook needed - env vars are handled by base shell
  shellHook = "";

  # No extra env vars needed - handled by centralized env.nix
  env = { };
}
