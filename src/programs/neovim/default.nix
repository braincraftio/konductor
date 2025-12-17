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

      # Session options - include globals for barbar buffer order persistence
      sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,globals";

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

      # Treesitter-based folding
      foldmethod = "expr";
      foldexpr = "v:lua.vim.treesitter.foldexpr()";
      foldcolumn = "0";      # Hide fold column
      foldlevel = 99;        # Start with all folds open
      foldlevelstart = 99;   # Start with all folds open
      foldenable = true;
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
      # Quit (use :w for save - standard vim, avoids <leader>wa/wr workspace overlap)
      { mode = "n"; key = "<leader>q"; action = "<cmd>q<cr>"; options.desc = "Quit"; }
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<cr>"; }
      { mode = "i"; key = "jk"; action = "<Esc>"; options.desc = "Exit insert mode"; }

      # LSP keymaps
      { mode = "n"; key = "<leader>lf"; action = "<cmd>lua vim.lsp.buf.format()<cr>"; options.desc = "Format buffer"; }
      { mode = "n"; key = "<leader>li"; action = "<cmd>LspInfo<cr>"; options.desc = "LSP Info"; }
      { mode = "n"; key = "<leader>lr"; action = "<cmd>LspRestart<cr>"; options.desc = "LSP Restart"; }
      { mode = "n"; key = "<leader>ll"; action = "<cmd>lua vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())<cr>"; options.desc = "Toggle inlay hints"; }
      { mode = "n"; key = "<leader>ls"; action = "<cmd>Telescope lsp_document_symbols<cr>"; options.desc = "Document symbols"; }
      { mode = "n"; key = "<leader>lS"; action = "<cmd>Telescope lsp_workspace_symbols<cr>"; options.desc = "Workspace symbols"; }
      { mode = "n"; key = "<leader>lD"; action = "<cmd>Telescope diagnostics<cr>"; options.desc = "Workspace diagnostics"; }

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
      { mode = "t"; key = "jk"; action = "<C-\\><C-n>"; options.desc = "Exit terminal mode"; }

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

      # Buffer navigation (barbar)
      { mode = "n"; key = "<S-h>"; action = "<cmd>BufferPrevious<cr>"; options.desc = "Previous buffer"; }
      { mode = "n"; key = "<S-l>"; action = "<cmd>BufferNext<cr>"; options.desc = "Next buffer"; }
      { mode = "n"; key = "[b"; action = "<cmd>BufferPrevious<cr>"; options.desc = "Previous buffer"; }
      { mode = "n"; key = "]b"; action = "<cmd>BufferNext<cr>"; options.desc = "Next buffer"; }
      { mode = "n"; key = "<A-,>"; action = "<cmd>BufferPrevious<cr>"; options.desc = "Previous buffer"; }
      { mode = "n"; key = "<A-.>"; action = "<cmd>BufferNext<cr>"; options.desc = "Next buffer"; }
      { mode = "n"; key = "<A-<>"; action = "<cmd>BufferMovePrevious<cr>"; options.desc = "Move buffer left"; }
      { mode = "n"; key = "<A->>"; action = "<cmd>BufferMoveNext<cr>"; options.desc = "Move buffer right"; }
      # Buffer position jumping
      { mode = "n"; key = "<A-1>"; action = "<cmd>BufferGoto 1<cr>"; options.desc = "Go to buffer 1"; }
      { mode = "n"; key = "<A-2>"; action = "<cmd>BufferGoto 2<cr>"; options.desc = "Go to buffer 2"; }
      { mode = "n"; key = "<A-3>"; action = "<cmd>BufferGoto 3<cr>"; options.desc = "Go to buffer 3"; }
      { mode = "n"; key = "<A-4>"; action = "<cmd>BufferGoto 4<cr>"; options.desc = "Go to buffer 4"; }
      { mode = "n"; key = "<A-5>"; action = "<cmd>BufferGoto 5<cr>"; options.desc = "Go to buffer 5"; }
      { mode = "n"; key = "<A-6>"; action = "<cmd>BufferGoto 6<cr>"; options.desc = "Go to buffer 6"; }
      { mode = "n"; key = "<A-7>"; action = "<cmd>BufferGoto 7<cr>"; options.desc = "Go to buffer 7"; }
      { mode = "n"; key = "<A-8>"; action = "<cmd>BufferGoto 8<cr>"; options.desc = "Go to buffer 8"; }
      { mode = "n"; key = "<A-9>"; action = "<cmd>BufferGoto 9<cr>"; options.desc = "Go to buffer 9"; }
      { mode = "n"; key = "<A-0>"; action = "<cmd>BufferLast<cr>"; options.desc = "Go to last buffer"; }
      # Buffer pinning
      { mode = "n"; key = "<A-p>"; action = "<cmd>BufferPin<cr>"; options.desc = "Pin/unpin buffer"; }
      { mode = "n"; key = "<leader>bp"; action = "<cmd>BufferPin<cr>"; options.desc = "Pin buffer"; }
      { mode = "n"; key = "<leader>bP"; action = "<cmd>BufferCloseAllButPinned<cr>"; options.desc = "Close unpinned buffers"; }
      { mode = "n"; key = "<leader>bgp"; action = "<cmd>BufferGotoPinned<cr>"; options.desc = "Go to pinned buffer"; }
      { mode = "n"; key = "<leader>bgu"; action = "<cmd>BufferGotoUnpinned<cr>"; options.desc = "Go to unpinned buffer"; }
      # Buffer closing
      { mode = "n"; key = "<A-c>"; action = "<cmd>BufferClose<cr>"; options.desc = "Close buffer"; }
      { mode = "n"; key = "<leader>bd"; action = "<cmd>BufferClose<cr>"; options.desc = "Close buffer"; }
      { mode = "n"; key = "<leader>bD"; action = "<cmd>BufferWipeout<cr>"; options.desc = "Wipeout buffer"; }
      { mode = "n"; key = "<leader>bx"; action = "<cmd>BufferCloseAllButCurrentOrPinned<cr>"; options.desc = "Close other buffers"; }
      { mode = "n"; key = "<leader>bO"; action = "<cmd>BufferCloseAllButCurrent<cr>"; options.desc = "Close all but current"; }
      { mode = "n"; key = "<leader>bv"; action = "<cmd>BufferCloseAllButVisible<cr>"; options.desc = "Close hidden buffers"; }
      { mode = "n"; key = "<leader>br"; action = "<cmd>BufferCloseBuffersRight<cr>"; options.desc = "Close buffers to right"; }
      { mode = "n"; key = "<leader>bl"; action = "<cmd>BufferCloseBuffersLeft<cr>"; options.desc = "Close buffers to left"; }
      { mode = "n"; key = "<leader>bR"; action = "<cmd>BufferRestore<cr>"; options.desc = "Restore closed buffer"; }
      # Buffer picking (jump mode)
      { mode = "n"; key = "<C-p>"; action = "<cmd>BufferPick<cr>"; options.desc = "Pick buffer (jump)"; }
      { mode = "n"; key = "<leader>bs"; action = "<cmd>BufferPick<cr>"; options.desc = "Pick buffer (jump mode)"; }
      { mode = "n"; key = "<leader>bS"; action = "<cmd>BufferPickDelete<cr>"; options.desc = "Pick buffer to close"; }
      # Buffer position (leader variants)
      { mode = "n"; key = "<leader>b1"; action = "<cmd>BufferGoto 1<cr>"; options.desc = "Go to buffer 1"; }
      { mode = "n"; key = "<leader>b2"; action = "<cmd>BufferGoto 2<cr>"; options.desc = "Go to buffer 2"; }
      { mode = "n"; key = "<leader>b3"; action = "<cmd>BufferGoto 3<cr>"; options.desc = "Go to buffer 3"; }
      { mode = "n"; key = "<leader>b4"; action = "<cmd>BufferGoto 4<cr>"; options.desc = "Go to buffer 4"; }
      { mode = "n"; key = "<leader>b5"; action = "<cmd>BufferGoto 5<cr>"; options.desc = "Go to buffer 5"; }
      { mode = "n"; key = "<leader>b0"; action = "<cmd>BufferLast<cr>"; options.desc = "Go to last buffer"; }
      { mode = "n"; key = "<leader>bf"; action = "<cmd>BufferFirst<cr>"; options.desc = "Go to first buffer"; }
      # Buffer scrolling (when tabs overflow)
      { mode = "n"; key = "<leader>b["; action = "<cmd>BufferScrollLeft<cr>"; options.desc = "Scroll tabline left"; }
      { mode = "n"; key = "<leader>b]"; action = "<cmd>BufferScrollRight<cr>"; options.desc = "Scroll tabline right"; }
      # Buffer sorting
      { mode = "n"; key = "<leader>bon"; action = "<cmd>BufferOrderByName<cr>"; options.desc = "Sort by name"; }
      { mode = "n"; key = "<leader>bod"; action = "<cmd>BufferOrderByDirectory<cr>"; options.desc = "Sort by directory"; }
      { mode = "n"; key = "<leader>bol"; action = "<cmd>BufferOrderByLanguage<cr>"; options.desc = "Sort by language"; }
      { mode = "n"; key = "<leader>bob"; action = "<cmd>BufferOrderByBufferNumber<cr>"; options.desc = "Sort by buffer number"; }
      { mode = "n"; key = "<leader>bow"; action = "<cmd>BufferOrderByWindowNumber<cr>"; options.desc = "Sort by window number"; }
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
      # LSP document highlighting on cursor hold
      {
        event = "LspAttach";
        callback.__raw = ''
          function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client.supports_method("textDocument/documentHighlight") then
              local group = vim.api.nvim_create_augroup("lsp_document_highlight_" .. args.buf, { clear = true })
              vim.api.nvim_create_autocmd("CursorHold", {
                group = group,
                buffer = args.buf,
                callback = function()
                  vim.lsp.buf.document_highlight()
                end,
              })
              vim.api.nvim_create_autocmd("CursorMoved", {
                group = group,
                buffer = args.buf,
                callback = function()
                  vim.lsp.buf.clear_references()
                end,
              })
            end
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


      # Fuzzy finder (telescope.nvim) - L4 Mature
      telescope = {
        enable = true;
        settings = {
          defaults = {
            # === Visual appearance ===
            prompt_prefix = "   ";
            selection_caret = " ";
            entry_prefix = "  ";
            multi_icon = " ";
            color_devicons = true;
            winblend = 0;
            border = true;
            borderchars = [ "─" "│" "─" "│" "╭" "╮" "╯" "╰" ];

            # === Layout configuration ===
            layout_strategy = "horizontal";
            layout_config = {
              horizontal = {
                prompt_position = "top";
                preview_width = 0.55;
                results_width = 0.8;
              };
              vertical = {
                mirror = false;
                preview_cutoff = 40;
              };
              center = {
                width = 0.6;
                height = 0.5;
              };
              width = 0.87;
              height = 0.80;
              preview_cutoff = 120;
            };

            # === Behavior ===
            sorting_strategy = "ascending";
            selection_strategy = "reset";
            scroll_strategy = "cycle";
            initial_mode = "insert";
            path_display = [ "truncate" ];
            dynamic_preview_title = true;

            # === File filtering ===
            hidden = true;
            file_ignore_patterns = [
              "^%.git/"
              "%.git/"
              "__pycache__/"
              "^node_modules/"
              "node_modules/"
              "^target/"
              "^result"
              "%.lock$"
              "^%.cache/"
            ];

            # === Preview configuration ===
            preview = {
              treesitter = true;
              filesize_limit = 1;      # MB - disable preview for large files
              timeout = 250;           # ms
            };

            # === Keymaps within telescope ===
            # Using __raw for proper Lua table syntax with special keys
            mappings.__raw = ''
              {
                i = {
                  -- Navigation
                  ["<C-j>"] = require("telescope.actions").move_selection_next,
                  ["<C-k>"] = require("telescope.actions").move_selection_previous,
                  ["<C-n>"] = require("telescope.actions").move_selection_next,
                  ["<C-p>"] = require("telescope.actions").move_selection_previous,
                  -- Opening
                  ["<CR>"] = require("telescope.actions").select_default,
                  ["<C-x>"] = require("telescope.actions").select_horizontal,
                  ["<C-v>"] = require("telescope.actions").select_vertical,
                  ["<C-t>"] = require("telescope.actions").select_tab,
                  -- Preview scrolling
                  ["<C-u>"] = require("telescope.actions").preview_scrolling_up,
                  ["<C-d>"] = require("telescope.actions").preview_scrolling_down,
                  ["<C-f>"] = require("telescope.actions").preview_scrolling_left,
                  ["<C-b>"] = require("telescope.actions").preview_scrolling_right,
                  -- Multi-select
                  ["<Tab>"] = require("telescope.actions").toggle_selection + require("telescope.actions").move_selection_worse,
                  ["<S-Tab>"] = require("telescope.actions").toggle_selection + require("telescope.actions").move_selection_better,
                  ["<C-q>"] = require("telescope.actions").send_selected_to_qflist + require("telescope.actions").open_qflist,
                  -- Misc
                  ["<C-c>"] = require("telescope.actions").close,
                  ["<C-/>"] = require("telescope.actions").which_key,
                },
                n = {
                  -- Navigation
                  ["j"] = require("telescope.actions").move_selection_next,
                  ["k"] = require("telescope.actions").move_selection_previous,
                  ["H"] = require("telescope.actions").move_to_top,
                  ["M"] = require("telescope.actions").move_to_middle,
                  ["L"] = require("telescope.actions").move_to_bottom,
                  ["gg"] = require("telescope.actions").move_to_top,
                  ["G"] = require("telescope.actions").move_to_bottom,
                  -- Opening
                  ["<CR>"] = require("telescope.actions").select_default,
                  ["s"] = require("telescope.actions").select_horizontal,
                  ["v"] = require("telescope.actions").select_vertical,
                  ["t"] = require("telescope.actions").select_tab,
                  -- Preview
                  ["<C-u>"] = require("telescope.actions").preview_scrolling_up,
                  ["<C-d>"] = require("telescope.actions").preview_scrolling_down,
                  -- Multi-select
                  ["<Tab>"] = require("telescope.actions").toggle_selection + require("telescope.actions").move_selection_worse,
                  ["<S-Tab>"] = require("telescope.actions").toggle_selection + require("telescope.actions").move_selection_better,
                  -- Close
                  ["q"] = require("telescope.actions").close,
                  ["<Esc>"] = require("telescope.actions").close,
                  ["?"] = require("telescope.actions").which_key,
                },
              }
            '';
          };

          # === Picker-specific configuration ===
          pickers = {
            # File pickers
            find_files = {
              hidden = true;
              no_ignore = false;
              follow = true;
              find_command = [ "fd" "--type" "f" "--strip-cwd-prefix" "--hidden" "--exclude" ".git" ];
            };
            live_grep = {
              additional_args = [ "--hidden" "--glob" "!.git/*" "--smart-case" ];
            };
            grep_string = {
              additional_args = [ "--hidden" "--glob" "!.git/*" ];
            };
            git_files = {
              show_untracked = true;
            };

            # Buffer/file pickers
            buffers = {
              show_all_buffers = true;
              sort_lastused = true;
              sort_mru = true;
              ignore_current_buffer = true;
              previewer = false;
              mappings.__raw = ''
                {
                  i = { ["<C-d>"] = require("telescope.actions").delete_buffer },
                  n = { ["d"] = require("telescope.actions").delete_buffer },
                }
              '';
            };
            oldfiles = {
              only_cwd = true;
            };

            # LSP pickers
            lsp_references = { show_line = true; };
            lsp_definitions = { show_line = true; };
            lsp_implementations = { show_line = true; };
            lsp_type_definitions = { show_line = true; };
            lsp_document_symbols = { symbol_width = 50; };
            lsp_workspace_symbols = { symbol_width = 50; };
            diagnostics = {
              bufnr = 0; # Current buffer by default
              line_width = "full";
              severity_limit = "hint";
            };

            # Git pickers
            git_commits = { git_command = [ "git" "log" "--oneline" "--decorate" "--all" ]; };
            git_bcommits = { git_command = [ "git" "log" "--oneline" "--decorate" ]; };
            git_branches = { show_remote_tracking_branches = true; };
            git_status = { git_icons = { added = "+"; changed = "~"; deleted = "-"; renamed = "➜"; untracked = "?"; }; };

            # Vim pickers
            commands = { show_buf_command = true; };
            keymaps = { show_plug = false; };
            help_tags = { };
            man_pages = { sections = [ "1" "2" "3" "5" "8" ]; };
            marks = { };
            registers = { };
            quickfix = { };
            loclist = { };
            colorscheme = { enable_preview = true; };
            highlights = { };
            vim_options = { };
            autocommands = { };
            spell_suggest = { };
            filetypes = { };
            current_buffer_fuzzy_find = { skip_empty_lines = true; };

            # Special pickers
            resume = { };
            pickers = { };
            builtin = { include_extensions = true; };
            treesitter = { show_line = true; };
          };
        };

        # === Global keymaps ===
        keymaps = {
          # File navigation (most used)
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fw" = "grep_string";
          "<leader>fb" = "buffers";
          "<leader>fr" = "oldfiles";
          "<leader>fc" = "current_buffer_fuzzy_find";

          # Git pickers
          "<leader>gf" = "git_files";
          "<leader>gc" = "git_commits";
          "<leader>gC" = "git_bcommits";
          "<leader>gb" = "git_branches";
          "<leader>gS" = "git_status";
          "<leader>gT" = "git_stash";

          # LSP pickers (some defined elsewhere in keymaps section)
          # <leader>ls, <leader>lS, <leader>lD already mapped in keymaps

          # Vim/Neovim pickers
          "<leader>fH" = "help_tags";
          "<leader>fk" = "keymaps";
          "<leader>fC" = "commands";
          "<leader>fm" = "marks";
          "<leader>fR" = "registers";
          "<leader>fq" = "quickfix";
          "<leader>fl" = "loclist";
          "<leader>fj" = "jumplist";
          "<leader>fM" = "man_pages";
          "<leader>fo" = "vim_options";
          "<leader>fa" = "autocommands";
          "<leader>fT" = "filetypes";
          "<leader>fP" = "colorscheme";
          "<leader>fG" = "highlights";

          # Special pickers
          "<leader>f'" = "resume";
          "<leader>fp" = "pickers";
          "<leader>fB" = "builtin";
          "<leader>fZ" = "treesitter";  # Syntax tree (fz = fuzzy treesitter)
          "<leader>fS" = "spell_suggest";
        };

        # === Extensions ===
        extensions = {
          fzf-native = {
            enable = true;
            settings = {
              fuzzy = true;
              override_generic_sorter = true;
              override_file_sorter = true;
              case_mode = "smart_case";
            };
          };
        };
      };

      # Syntax highlighting and code parsing (nvim-treesitter)
      treesitter = {
        enable = true;
        # Use nix-provided grammars (installed at build time, not runtime)
        nixGrammars = true;
        # Specify grammars via nix - these are installed at build time
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bash c cpp css dockerfile go gomod gosum
          html http javascript json jsonc lua luadoc
          make markdown markdown_inline nix python query regex rust
          toml tsx typescript vim vimdoc xml yaml
          # norg - not in builtGrammars, only needed for neorg users
        ];
        settings = {
          # Core modules
          highlight = {
            enable = true;
            additional_vim_regex_highlighting = false; # Disable legacy regex (performance)
          };
          indent = {
            enable = true;
          };
          # Incremental selection - expand/contract selection by syntax nodes
          incremental_selection = {
            enable = true;
            keymaps = {
              init_selection = "<C-space>";    # Start selection
              node_incremental = "<C-space>";  # Expand to larger node
              scope_incremental = "<C-s>";     # Expand to scope
              node_decremental = "<C-backspace>"; # Shrink selection
            };
          };
          # Disable runtime parser installation - all grammars provided by nix
          auto_install = false;
          sync_install = false;
          # Do NOT set parser_install_dir - nixGrammars handles this
        };
      };

      # Treesitter textobjects - configured via extraConfigLua for full control
      treesitter-textobjects.enable = true;

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
        # Inlay hints (type annotations inline)
        inlayHints = true;
        keymaps = {
          silent = true;
          diagnostic = {
            "<leader>ld" = "open_float";
            "[d" = "goto_prev";
            "]d" = "goto_next";
            "[e" = {
              action = "goto_prev";
              desc = "Previous error";
            };
            "]e" = {
              action = "goto_next";
              desc = "Next error";
            };
          };
          lspBuf = {
            # Navigation (gr* prefix uses nvim 0.11 defaults: grr=refs, gri=impl, grt=typedef, grn=rename, gra=action)
            gd = "definition";
            gD = "declaration";
            # gr = "references";  # Removed - use <grr> (nvim 0.11 builtin)
            gI = "implementation";
            gy = "type_definition";
            # Documentation
            K = "hover";
            "<C-k>" = "signature_help";
            # Actions
            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
            # Workspace
            "<leader>wa" = "add_workspace_folder";
            "<leader>wr" = "remove_workspace_folder";
          };
        };
        servers = {
          # Explicitly disable removed LSP servers
          ansiblels.enable = false;

          # Nix - nil with nixpkgs-fmt
          nil_ls = {
            enable = true;
            settings = {
              formatting.command = [ "nixpkgs-fmt" ];
              nix = {
                flake = {
                  autoArchive = true;
                  autoEvalInputs = true;
                };
              };
            };
          };

          # Lua - configured for Neovim development
          lua_ls = {
            enable = true;
            settings = {
              telemetry.enable = false;
              completion.callSnippet = "Replace";
              diagnostics = {
                globals = [ "vim" "Snacks" ];
              };
              workspace = {
                checkThirdParty = false;
              };
              hint = {
                enable = true;
                arrayIndex = "Disable";
                setType = true;
                paramName = "All";
                paramType = true;
              };
            };
          };

          # Bash
          bashls = {
            enable = true;
            settings.bashIde = {
              globPattern = "*@(.sh|.inc|.bash|.command)";
            };
          };

          # YAML with schema support
          yamlls = {
            enable = true;
            settings.yaml = {
              keyOrdering = false;
              schemas = {
                kubernetes = "/*.k8s.yaml";
                "http://json.schemastore.org/github-workflow" = ".github/workflows/*";
                "http://json.schemastore.org/github-action" = ".github/action.{yml,yaml}";
                "http://json.schemastore.org/prettierrc" = ".prettierrc.{yml,yaml}";
              };
              validate = true;
              completion = true;
            };
          };

          # Markdown
          marksman.enable = true;

          # JSON with schema support
          jsonls = {
            enable = true;
            settings.json = {
              validate.enable = true;
            };
          };

          # Python - pyright with enhanced analysis
          pyright = {
            enable = true;
            settings.python = {
              analysis = {
                typeCheckingMode = "basic";
                autoSearchPaths = true;
                useLibraryCodeForTypes = true;
                diagnosticMode = "workspace";
              };
            };
          };

          # Go - gopls with all features
          gopls = {
            enable = true;
            settings.gopls = {
              analyses = {
                unusedparams = true;
                shadow = true;
                nilness = true;
                unusedwrite = true;
                useany = true;
              };
              staticcheck = true;
              gofumpt = true;
              usePlaceholders = true;
              hints = {
                assignVariableTypes = true;
                compositeLiteralFields = true;
                compositeLiteralTypes = true;
                constantValues = true;
                functionTypeParameters = true;
                parameterNames = true;
                rangeVariableTypes = true;
              };
            };
          };

          # Rust - rust-analyzer with clippy
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
            settings = {
              checkOnSave = true;
              check.command = "clippy";
              cargo = {
                allFeatures = true;
                loadOutDirsFromCheck = true;
              };
              procMacro.enable = true;
              inlayHints = {
                bindingModeHints.enable = true;
                closureReturnTypeHints.enable = "always";
                lifetimeElisionHints.enable = "always";
                parameterHints.enable = true;
                typeHints.enable = true;
              };
            };
          };

          # TypeScript/JavaScript
          ts_ls = {
            enable = true;
            settings = {
              typescript = {
                inlayHints = {
                  includeInlayParameterNameHints = "all";
                  includeInlayParameterNameHintsWhenArgumentMatchesName = false;
                  includeInlayFunctionParameterTypeHints = true;
                  includeInlayVariableTypeHints = true;
                  includeInlayPropertyDeclarationTypeHints = true;
                  includeInlayFunctionLikeReturnTypeHints = true;
                };
              };
              javascript = {
                inlayHints = {
                  includeInlayParameterNameHints = "all";
                  includeInlayParameterNameHintsWhenArgumentMatchesName = false;
                  includeInlayFunctionParameterTypeHints = true;
                  includeInlayVariableTypeHints = true;
                  includeInlayPropertyDeclarationTypeHints = true;
                  includeInlayFunctionLikeReturnTypeHints = true;
                };
              };
            };
          };
        };
      };

      # Completion engine (L4 Mature)
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          # Performance tuning
          performance = {
            debounce = 60;
            throttle = 30;
            fetching_timeout = 500;
            async_budget = 1;
            max_view_entries = 100;
          };

          # Preselect behavior
          preselect = "cmp.PreselectMode.Item";

          # Completion triggering
          completion = {
            completeopt = "menu,menuone,noselect";
            keyword_length = 1;
          };

          # Matching behavior
          matching = {
            disallow_fuzzy_matching = false;
            disallow_partial_fuzzy_matching = true;
            disallow_partial_matching = false;
            disallow_prefix_unmatching = false;
          };

          # Window styling - bordered with proper highlights
          window = {
            completion = {
              border = "rounded";
              winhighlight = "Normal:CmpNormal,FloatBorder:CmpBorder,CursorLine:CmpSel,Search:None";
              scrollbar = true;
              col_offset = 0;
              side_padding = 1;
            };
            documentation = {
              border = "rounded";
              winhighlight = "Normal:CmpDocNormal,FloatBorder:CmpDocBorder";
              max_height = 20;
              max_width = 80;
            };
          };

          # Formatting - icons and labels
          formatting = {
            fields = [ "kind" "abbr" "menu" ];
            expandable_indicator = true;
            format.__raw = ''
              function(entry, vim_item)
                -- Kind icons
                local kind_icons = {
                  Text = "󰉿",
                  Method = "󰆧",
                  Function = "󰊕",
                  Constructor = "",
                  Field = "󰜢",
                  Variable = "󰀫",
                  Class = "󰠱",
                  Interface = "",
                  Module = "",
                  Property = "󰜢",
                  Unit = "󰑭",
                  Value = "󰎠",
                  Enum = "",
                  Keyword = "󰌋",
                  Snippet = "",
                  Color = "󰏘",
                  File = "󰈙",
                  Reference = "󰈇",
                  Folder = "󰉋",
                  EnumMember = "",
                  Constant = "󰏿",
                  Struct = "󰙅",
                  Event = "",
                  Operator = "󰆕",
                  TypeParameter = "",
                  Copilot = "",
                }
                vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind] or "", vim_item.kind)
                -- Source labels
                vim_item.menu = ({
                  copilot = "[AI]",
                  nvim_lsp = "[LSP]",
                  luasnip = "[Snip]",
                  buffer = "[Buf]",
                  path = "[Path]",
                  cmdline = "[Cmd]",
                })[entry.source.name] or ""
                return vim_item
              end
            '';
          };

          # Sorting - explicit comparators
          sorting = {
            priority_weight = 2;
            comparators = [
              "require('cmp.config.compare').offset"
              "require('cmp.config.compare').exact"
              "require('cmp.config.compare').score"
              "require('cmp.config.compare').recently_used"
              "require('cmp.config.compare').locality"
              "require('cmp.config.compare').kind"
              "require('cmp.config.compare').length"
              "require('cmp.config.compare').order"
            ];
          };

          # Keymaps - comprehensive navigation
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-u>" = "cmp.mapping.scroll_docs(4)";
            "<C-e>" = "cmp.mapping.abort()";
            "<C-y>" = "cmp.mapping.confirm({ select = true })";
            "<CR>" = "cmp.mapping.confirm({ select = false })";
            "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }), {'i', 's'})";
            "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }), {'i', 's'})";
            "<C-n>" = "cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert })";
            "<C-p>" = "cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert })";
          };

          # Sources - ordered by priority with group indices
          sources = [
            { name = "copilot"; group_index = 1; priority = 100; }
            { name = "nvim_lsp"; group_index = 1; priority = 90; }
            { name = "luasnip"; group_index = 1; priority = 80; }
            { name = "path"; group_index = 2; priority = 70; }
            { name = "buffer"; group_index = 2; priority = 60; keyword_length = 3; }
          ];

          # Experimental features
          experimental = {
            ghost_text = {
              hl_group = "CmpGhostText";
            };
          };
        };
      };

      # Cmdline completion
      cmp-cmdline.enable = true;

      # Snippets
      luasnip = {
        enable = true;
        fromVscode = [{ }];
      };

      # Code formatting (conform.nvim)
      conform-nvim = {
        enable = true;
        settings = {
          # Formatters by filetype
          formatters_by_ft = {
            # Nix
            nix = [ "nixpkgs_fmt" ];
            # Python - isort for imports, then black for formatting
            python = [ "isort" "black" ];
            # Rust
            rust = [ "rustfmt" ];
            # Go - format then organize imports
            go = [ "gofmt" "goimports" ];
            # JavaScript/TypeScript ecosystem
            javascript = [ "prettier" ];
            typescript = [ "prettier" ];
            javascriptreact = [ "prettier" ];
            typescriptreact = [ "prettier" ];
            vue = [ "prettier" ];
            css = [ "prettier" ];
            scss = [ "prettier" ];
            html = [ "prettier" ];
            # Data formats
            json = [ "prettier" ];
            yaml = [ "prettier" ];
            toml = [ "taplo" ];
            # Documentation
            markdown = [ "prettier" ];
            # Shell
            bash = [ "shfmt" ];
            sh = [ "shfmt" ];
            zsh = [ "shfmt" ];
            # Lua
            lua = [ "stylua" ];
            # Docker
            dockerfile = [ "hadolint" ];
            # Fallback for all filetypes - trim whitespace
            "_" = [ "trim_whitespace" "trim_newlines" ];
          };

          # Format on save configuration
          format_on_save = {
            timeout_ms = 1000;
            lsp_format = "fallback";  # Use LSP if no formatter available
            quiet = false;
          };

          # Default format options
          default_format_opts = {
            timeout_ms = 1000;
            lsp_format = "fallback";
          };

          # Notifications
          notify_on_error = true;
          notify_no_formatters = false;  # Don't spam when no formatters

          # Formatter-specific customizations
          formatters = {
            shfmt = {
              prepend_args = [ "-i" "2" "-ci" "-bn" ];  # 2-space indent, case indent, binary newline
            };
            prettier = {
              prepend_args = [ "--prose-wrap" "always" ];
            };
            black = {
              prepend_args = [ "--line-length" "88" ];
            };
            stylua = {
              prepend_args = [ "--indent-type" "Spaces" "--indent-width" "2" ];
            };
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

      # Command discovery and keymap hints (which-key)
      which-key = {
        enable = true;
        settings = {
          # Timing
          delay = 300;  # Show popup after 300ms

          # Icons
          icons = {
            breadcrumb = "»";
            separator = "➜";
            group = "+";
            ellipsis = "…";
            mappings = true;  # Enable icons for mappings
            colors = true;    # Use highlight colors
            keys = {
              Up = " ";
              Down = " ";
              Left = " ";
              Right = " ";
              C = "󰘴 ";
              M = "󰘵 ";
              D = "󰘳 ";
              S = "󰘶 ";
              CR = "󰌑 ";
              Esc = "󱊷 ";
              ScrollWheelDown = "󱕐 ";
              ScrollWheelUp = "󱕑 ";
              NL = "󰌑 ";
              BS = "󰁮";
              Space = "󱁐 ";
              Tab = "󰌒 ";
              F1 = "󱊫";
              F2 = "󱊬";
              F3 = "󱊭";
              F4 = "󱊮";
              F5 = "󱊯";
              F6 = "󱊰";
              F7 = "󱊱";
              F8 = "󱊲";
              F9 = "󱊳";
              F10 = "󱊴";
              F11 = "󱊵";
              F12 = "󱊶";
            };
          };

          # Window appearance
          win = {
            border = "rounded";
            padding = [ 1 2 ];
            title = true;
            title_pos = "center";
            zindex = 1000;
          };

          # Layout
          layout = {
            width = { min = 20; };
            spacing = 3;
          };

          # Built-in plugins
          plugins = {
            marks = true;      # Shows marks on ' and `
            registers = true;  # Shows registers on " and <C-r>
            spelling = {
              enabled = true;
              suggestions = 20;
            };
            presets = {
              operators = true;     # Help for operators like d, y, c
              motions = true;       # Help for motions
              text_objects = true;  # Help for text objects (a, i)
              windows = true;       # Help for window commands <C-w>
              nav = true;           # Help for navigation
              z = true;             # Help for z commands (folds, spelling)
              g = true;             # Help for g commands
            };
          };

          # Sorting
          sort = [ "local" "order" "group" "alphanum" "mod" ];

          # Disable notifications for overlapping keymaps
          notify = false;

          # Show help and keys
          show_help = true;
          show_keys = true;
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
      # Barbar.nvim - tabline with re-orderable, auto-sizing, clickable tabs
      ((buildVimPlugin {
        name = "barbar.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "romgrk";
          repo = "barbar.nvim";
          rev = "v1.9.1";
          sha256 = "sha256-XEHEK2Z97YSS4/flsXSdle/mHKhp6maEg4uXwst88m8=";
        };
      }).overrideAttrs (old: {
        doCheck = false;
        # Auto-setup barbar on plugin load
        postInstall = (old.postInstall or "") + ''
          mkdir -p $out/plugin
          cat > $out/plugin/barbar-setup.lua << 'EOF'
          -- Disable auto-setup, we configure manually
          vim.g.barbar_auto_setup = false
          EOF
        '';
      }))

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
          -- Snacks.nvim is configured via extraConfigLua for proper timing
          vim.g.snacks_loaded = true
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
      -- Diagnostic display configuration
      vim.diagnostic.config({
        virtual_text = {
          spacing = 4,
          prefix = "●",
        },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = "󰌵",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = {
          border = "rounded",
          source = "if_many",
          header = "",
          prefix = "",
        },
      })

      -- nvim-cmp Highlight Groups (catppuccin integration)
      local colors = require("catppuccin.palettes").get_palette("macchiato")
      vim.api.nvim_set_hl(0, "CmpNormal", { bg = colors.surface0 })
      vim.api.nvim_set_hl(0, "CmpBorder", { fg = colors.blue, bg = colors.surface0 })
      vim.api.nvim_set_hl(0, "CmpSel", { bg = colors.surface1, bold = true })
      vim.api.nvim_set_hl(0, "CmpDocNormal", { bg = colors.surface0 })
      vim.api.nvim_set_hl(0, "CmpDocBorder", { fg = colors.teal, bg = colors.surface0 })
      vim.api.nvim_set_hl(0, "CmpGhostText", { fg = colors.overlay0, italic = true })
      -- Kind-specific highlights
      vim.api.nvim_set_hl(0, "CmpItemKindCopilot", { fg = colors.green })
      vim.api.nvim_set_hl(0, "CmpItemKindSnippet", { fg = colors.mauve })
      vim.api.nvim_set_hl(0, "CmpItemKindFunction", { fg = colors.blue })
      vim.api.nvim_set_hl(0, "CmpItemKindMethod", { fg = colors.blue })
      vim.api.nvim_set_hl(0, "CmpItemKindVariable", { fg = colors.flamingo })
      vim.api.nvim_set_hl(0, "CmpItemKindKeyword", { fg = colors.red })

      -- nvim-cmp Cmdline Configuration
      local cmp = require('cmp')
      -- Cmdline : completion
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = 'path' }
        }, {
          { name = 'cmdline', option = { ignore_cmds = { 'Man', '!' } } }
        })
      })
      -- Cmdline / and ? search completion
      cmp.setup.cmdline({ '/', '?' }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = 'buffer' }
        }
      })

      -- Snacks.nvim Configuration (utilities)
      local snacks_ok, snacks = pcall(require, "snacks")
      if snacks_ok then
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
          -- Disable features we don't use
          dashboard = { enabled = false },
          explorer = { enabled = false },
          picker = { enabled = false },
          image = { enabled = false },  -- Using image.nvim instead
        })
      end

      -- Which-Key Group Registrations (organize keymap discovery)
      local wk = require("which-key")
      wk.add({
        -- Leader key groups
        { "<leader>a", group = "AI/Copilot", icon = "󰚩" },
        { "<leader>b", group = "Buffers", icon = "󰓩" },
        { "<leader>bs", group = "Sort buffers", icon = "󰒺" },
        { "<leader>c", group = "Code", icon = "" },
        { "<leader>f", group = "Find/Files", icon = "" },
        { "<leader>g", group = "Git", icon = "" },
        { "<leader>l", group = "LSP", icon = "" },
        { "<leader>m", group = "Markdown", icon = "" },
        { "<leader>p", group = "Peek", icon = "󰈈" },
        { "<leader>r", group = "HTTP/REST", icon = "󰖟" },
        { "<leader>t", group = "Terminal", icon = "" },
        { "<leader>x", group = "Swap/Exchange", icon = "󰓡" },

        -- Bracket motions (treesitter textobjects)
        { "]", group = "Next" },
        { "[", group = "Previous" },

        -- Text objects (visual/operator mode)
        { "a", group = "Around", mode = { "x", "o" } },
        { "i", group = "Inside", mode = { "x", "o" } },

        -- g prefix commands
        { "g", group = "Goto/Actions" },
        { "gc", group = "Comment" },

        -- z prefix commands
        { "z", group = "Fold/Scroll" },
      })

      -- Treesitter Textobjects Configuration (full control)
      require('nvim-treesitter.configs').setup({
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              -- Function textobjects
              ["af"] = { query = "@function.outer", desc = "outer function" },
              ["if"] = { query = "@function.inner", desc = "inner function" },
              -- Class textobjects
              ["ac"] = { query = "@class.outer", desc = "outer class" },
              ["ic"] = { query = "@class.inner", desc = "inner class" },
              -- Parameter/argument textobjects
              ["aa"] = { query = "@parameter.outer", desc = "outer argument" },
              ["ia"] = { query = "@parameter.inner", desc = "inner argument" },
              -- Conditional textobjects
              ["ai"] = { query = "@conditional.outer", desc = "outer conditional" },
              ["ii"] = { query = "@conditional.inner", desc = "inner conditional" },
              -- Loop textobjects
              ["al"] = { query = "@loop.outer", desc = "outer loop" },
              ["il"] = { query = "@loop.inner", desc = "inner loop" },
              -- Block textobjects
              ["ab"] = { query = "@block.outer", desc = "outer block" },
              ["ib"] = { query = "@block.inner", desc = "inner block" },
              -- Comment textobjects
              ["a/"] = { query = "@comment.outer", desc = "outer comment" },
              -- Call/invocation textobjects
              ["am"] = { query = "@call.outer", desc = "outer method call" },
              ["im"] = { query = "@call.inner", desc = "inner method call" },
            },
            selection_modes = {
              ["@parameter.outer"] = "v",
              ["@function.outer"] = "V",
              ["@class.outer"] = "V",
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["<leader>xp"] = { query = "@parameter.inner", desc = "Swap next parameter" },
              ["<leader>xf"] = { query = "@function.outer", desc = "Swap next function" },
            },
            swap_previous = {
              ["<leader>xP"] = { query = "@parameter.inner", desc = "Swap prev parameter" },
              ["<leader>xF"] = { query = "@function.outer", desc = "Swap prev function" },
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = { query = "@function.outer", desc = "Next function start" },
              ["]c"] = { query = "@class.outer", desc = "Next class start" },
              ["]a"] = { query = "@parameter.inner", desc = "Next argument" },
              ["]i"] = { query = "@conditional.outer", desc = "Next conditional" },
              ["]l"] = { query = "@loop.outer", desc = "Next loop" },
              ["]m"] = { query = "@call.outer", desc = "Next method call" },
            },
            goto_next_end = {
              ["]F"] = { query = "@function.outer", desc = "Next function end" },
              ["]C"] = { query = "@class.outer", desc = "Next class end" },
            },
            goto_previous_start = {
              ["[f"] = { query = "@function.outer", desc = "Prev function start" },
              ["[c"] = { query = "@class.outer", desc = "Prev class start" },
              ["[a"] = { query = "@parameter.inner", desc = "Prev argument" },
              ["[i"] = { query = "@conditional.outer", desc = "Prev conditional" },
              ["[l"] = { query = "@loop.outer", desc = "Prev loop" },
              ["[m"] = { query = "@call.outer", desc = "Prev method call" },
            },
            goto_previous_end = {
              ["[F"] = { query = "@function.outer", desc = "Prev function end" },
              ["[C"] = { query = "@class.outer", desc = "Prev class end" },
            },
          },
        },
      })

      -- Repeatable movements with ; and ,
      local ts_repeat_move = require("nvim-treesitter.textobjects.repeatable_move")
      vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat_move.repeat_last_move_next)
      vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat_move.repeat_last_move_previous)

      -- Barbar.nvim Configuration (tabline)
      require('barbar').setup({
        -- Enable animations for smooth transitions
        animation = true,

        -- Auto-hide disabled (-1) to always show tabline
        auto_hide = -1,

        -- Enable tabpages indicator (top right)
        tabpages = true,

        -- Clickable tabs (left=go, middle=close)
        clickable = true,

        -- Exclude non-file buffers from tabline
        exclude_ft = { 'qf', 'fugitive', 'fugitiveblame', 'httpResult', 'DressingInput' },
        exclude_name = { '[No Name]', 'COMMIT_EDITMSG' },

        -- Focus left buffer when closing (alternatives: 'previous', 'right')
        focus_on_close = 'left',

        -- Hide settings
        hide = {
          extensions = false,    -- Show file extensions
          inactive = false,      -- Show inactive buffers
        },

        -- Highlight settings for buffer states
        highlight_alternate = false,              -- Don't highlight alternate buffer differently
        highlight_inactive_file_icons = true,     -- Color icons even on inactive buffers
        highlight_visible = true,                 -- Highlight visible buffers in splits

        -- Icons configuration
        icons = {
          -- Buffer identification
          buffer_index = false,  -- Don't show buffer index
          buffer_number = false, -- Don't show buffer number

          -- Close button icon
          button = "",

          -- LSP Diagnostics in tabline
          diagnostics = {
            [vim.diagnostic.severity.ERROR] = { enabled = true, icon = ' ' },
            [vim.diagnostic.severity.WARN] = { enabled = true, icon = ' ' },
            [vim.diagnostic.severity.INFO] = { enabled = true, icon = ' ' },
            [vim.diagnostic.severity.HINT] = { enabled = true, icon = '󰌵' },
          },

          -- Git status via gitsigns integration
          gitsigns = {
            added = { enabled = true, icon = '+' },
            changed = { enabled = true, icon = '~' },
            deleted = { enabled = true, icon = '-' },
          },

          -- File type icons (requires nvim-web-devicons)
          filetype = {
            custom_colors = false,  -- Use nvim-web-devicons colors
            enabled = true,
          },

          -- Tab separators - using slanted style
          separator = { left = "", right = "" },
          separator_at_end = false,

          -- Modified buffer indicator
          modified = { button = '●' },

          -- Pinned buffer indicator
          pinned = { button = "", filename = true },

          -- Visual preset: 'default', 'powerline', or 'slanted'
          preset = 'slanted',

          -- Per-state icon overrides
          alternate = { filetype = { enabled = true } },
          current = { buffer_index = false },
          inactive = { button = '×' },
          visible = { modified = { buffer_number = false } },
        },

        -- Buffer insertion position
        insert_at_end = false,
        insert_at_start = false,

        -- Padding around tab names
        maximum_padding = 2,
        minimum_padding = 1,

        -- Buffer name length limits
        maximum_length = 30,
        minimum_length = 0,

        -- Jump mode: assign letters based on buffer filename
        semantic_letters = true,

        -- Sidebar offsets for file explorers
        sidebar_filetypes = {
          ['neo-tree'] = { event = 'BufWipeout', text = '  Files', align = 'center' },
          NvimTree = true,
          undotree = { text = 'Undo Tree', align = 'center' },
          Outline = { text = 'Symbols', align = 'right' },
          DiffviewFiles = { text = 'Diff View', align = 'left' },
        },

        -- Letter order for jump mode (home row first for qwerty)
        letters = 'asdfjkl;ghnmxcvbziowerutyqpASDFJKLGHNMXCVBZIOWERUTYQP',

        -- Name for unnamed buffers
        no_name_title = '[No Name]',

        -- Sorting options
        sort = {
          ignore_case = true,
        },
      })

      -- Catppuccin highlight integration for barbar
      -- Links barbar highlights to catppuccin-compatible groups
      local function setup_barbar_highlights()
        local colors = require('catppuccin.palettes').get_palette('macchiato')
        if not colors then return end

        -- Set highlight groups for barbar with catppuccin colors
        vim.api.nvim_set_hl(0, 'BufferCurrent', { fg = colors.text, bg = colors.surface0, bold = true })
        vim.api.nvim_set_hl(0, 'BufferCurrentMod', { fg = colors.peach, bg = colors.surface0, bold = true })
        vim.api.nvim_set_hl(0, 'BufferCurrentSign', { fg = colors.blue, bg = colors.surface0 })
        vim.api.nvim_set_hl(0, 'BufferCurrentTarget', { fg = colors.red, bg = colors.surface0, bold = true })

        vim.api.nvim_set_hl(0, 'BufferVisible', { fg = colors.subtext0, bg = colors.mantle })
        vim.api.nvim_set_hl(0, 'BufferVisibleMod', { fg = colors.peach, bg = colors.mantle })
        vim.api.nvim_set_hl(0, 'BufferVisibleSign', { fg = colors.blue, bg = colors.mantle })

        vim.api.nvim_set_hl(0, 'BufferInactive', { fg = colors.overlay0, bg = colors.mantle })
        vim.api.nvim_set_hl(0, 'BufferInactiveMod', { fg = colors.peach, bg = colors.mantle })
        vim.api.nvim_set_hl(0, 'BufferInactiveSign', { fg = colors.surface1, bg = colors.mantle })

        vim.api.nvim_set_hl(0, 'BufferTabpages', { fg = colors.blue, bg = colors.mantle, bold = true })
        vim.api.nvim_set_hl(0, 'BufferTabpageFill', { bg = colors.mantle })
        vim.api.nvim_set_hl(0, 'BufferOffset', { fg = colors.text, bg = colors.mantle, bold = true })
        vim.api.nvim_set_hl(0, 'BufferScrollArrow', { fg = colors.blue, bg = colors.mantle })
      end

      -- Apply highlights after colorscheme loads
      vim.api.nvim_create_autocmd('ColorScheme', {
        pattern = 'catppuccin*',
        callback = setup_barbar_highlights,
      })
      -- Also apply now if catppuccin is already loaded
      pcall(setup_barbar_highlights)

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

      -- Custom Terminal Integrations
      local Terminal = require('toggleterm.terminal').Terminal

      -- LazyGit - full-screen git TUI
      local lazygit = Terminal:new({
        cmd = "lazygit",
        hidden = true,
        direction = "float",
        float_opts = {
          border = "curved",
          width = function() return math.floor(vim.o.columns * 0.95) end,
          height = function() return math.floor(vim.o.lines * 0.95) end,
        },
        on_open = function(term)
          vim.cmd("startinsert!")
          -- Disable line numbers in lazygit
          vim.opt_local.number = false
          vim.opt_local.relativenumber = false
        end,
      })
      function _lazygit_toggle()
        lazygit:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>tg", "<cmd>lua _lazygit_toggle()<CR>", {noremap = true, silent = true, desc = "LazyGit"})

      -- Btop - system monitor
      local btop = Terminal:new({
        cmd = "btop",
        hidden = true,
        direction = "float",
        float_opts = {
          border = "curved",
          width = function() return math.floor(vim.o.columns * 0.9) end,
          height = function() return math.floor(vim.o.lines * 0.9) end,
        },
      })
      function _btop_toggle()
        btop:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>tb", "<cmd>lua _btop_toggle()<CR>", {noremap = true, silent = true, desc = "Btop system monitor"})

      -- Python REPL
      local python = Terminal:new({
        cmd = "python3",
        hidden = true,
        direction = "horizontal",
        on_open = function(term)
          vim.cmd("startinsert!")
        end,
      })
      function _python_toggle()
        python:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>tp", "<cmd>lua _python_toggle()<CR>", {noremap = true, silent = true, desc = "Python REPL"})

      -- Node REPL
      local node = Terminal:new({
        cmd = "node",
        hidden = true,
        direction = "horizontal",
        on_open = function(term)
          vim.cmd("startinsert!")
        end,
      })
      function _node_toggle()
        node:toggle()
      end
      vim.api.nvim_set_keymap("n", "<leader>tn", "<cmd>lua _node_toggle()<CR>", {noremap = true, silent = true, desc = "Node REPL"})

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
