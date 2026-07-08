# src/programs/neovim/keymaps.nix
# Workflow-oriented keybindings for all skill levels
#
# Layout Philosophy (Apple-simple, Material-elegant):
#   LEFT   - Explorer (<leader>e)     - File navigation
#   CENTER - Editor                   - Your code
#   RIGHT  - AI Panel                 - Claude (<leader>vv) / OpenCode (<leader>oo)
#   BOTTOM - Terminal (<leader>tt)    - Shell access
#
# AI Integration:
#   <leader>v* - Vibe group (Claude Code, Copilot)
#   <leader>o* - OpenCode (multi-provider AI agent with deep integration)
#   go{motion} - OpenCode operator (review with motion, e.g., goap = review paragraph)
#
# Navigation:
#   Ctrl+hjkl  - Move between splits AND tmux panes (vim-tmux-navigator;
#                works in terminal buffers too, hands off at edge windows)
#   jk         - Exit insert/terminal mode (universal escape)
#   <leader>w* - Window management group
#
# Design principles:
#   - Progressive disclosure: common actions first, power features in subgroups
#   - Mnemonic consistency: v=Vibe, o=OpenCode, f=Find, g=Git, t=Terminal
#   - Discoverable: which-key shows groups with icons and descriptions
#   - Efficient: experts can chain keys quickly, novices can explore
#
_:

{
  keymaps = [
    # =========================================================================
    # ESSENTIALS - No prefix, muscle memory
    # =========================================================================
    {
      mode = "n";
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
      options.desc = "Clear search";
    }
    {
      mode = "i";
      key = "jk";
      action = "<Esc>";
      options.desc = "Exit insert mode";
    }

    # Window navigation (Ctrl + hjkl): provided by plugins.tmux-navigator
    # (plugins.nix) — :TmuxNavigate* does wincmd AND hands off to
    # `tmux select-pane` at the edge window. Defining plain <C-w>h maps
    # here would shadow the plugin and break the tmux edge handoff.

    # Window resize (Ctrl + arrows)
    {
      mode = "n";
      key = "<C-Up>";
      action = "<cmd>resize +2<CR>";
      options.desc = "Increase height";
    }
    {
      mode = "n";
      key = "<C-Down>";
      action = "<cmd>resize -2<CR>";
      options.desc = "Decrease height";
    }
    {
      mode = "n";
      key = "<C-Left>";
      action = "<cmd>vertical resize -2<CR>";
      options.desc = "Decrease width";
    }
    {
      mode = "n";
      key = "<C-Right>";
      action = "<cmd>vertical resize +2<CR>";
      options.desc = "Increase width";
    }

    # Line movement (Alt + jk)
    {
      mode = "n";
      key = "<A-j>";
      action = "<cmd>m .+1<CR>==";
      options.desc = "Move line down";
    }
    {
      mode = "n";
      key = "<A-k>";
      action = "<cmd>m .-2<CR>==";
      options.desc = "Move line up";
    }
    {
      mode = "v";
      key = "<A-j>";
      action = ":m '>+1<CR>gv=gv";
      options.desc = "Move selection down";
    }
    {
      mode = "v";
      key = "<A-k>";
      action = ":m '<-2<CR>gv=gv";
      options.desc = "Move selection up";
    }

    # Better indenting (stay in visual mode)
    {
      mode = "v";
      key = "<";
      action = "<gv";
    }
    {
      mode = "v";
      key = ">";
      action = ">gv";
    }

    # Tmux ⇄ Neovim navigation — all modes explicit.
    # g:tmux_navigator_no_mappings = 1 (options.nix) disables the plugin's
    # own maps because its t-mode maps use \<C-w>: which leaks command text
    # into terminal programs (claude-code, opencode). We set both n-mode
    # and t-mode maps here using <cmd> which bypasses terminal input.
    {
      mode = "n";
      key = "<C-h>";
      action = "<cmd>TmuxNavigateLeft<CR>";
      options = {
        desc = "Go to left window/pane";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<C-j>";
      action = "<cmd>TmuxNavigateDown<CR>";
      options = {
        desc = "Go to lower window/pane";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<C-k>";
      action = "<cmd>TmuxNavigateUp<CR>";
      options = {
        desc = "Go to upper window/pane";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<C-l>";
      action = "<cmd>TmuxNavigateRight<CR>";
      options = {
        desc = "Go to right window/pane";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<C-\\>";
      action = "<cmd>TmuxNavigatePrevious<CR>";
      options = {
        desc = "Go to previous window/pane";
        silent = true;
      };
    }
    {
      mode = "t";
      key = "<C-h>";
      action = "<cmd>TmuxNavigateLeft<CR>";
      options.desc = "Go to left window/pane";
    }
    {
      mode = "t";
      key = "<C-j>";
      action = "<cmd>TmuxNavigateDown<CR>";
      options.desc = "Go to lower window/pane";
    }
    {
      mode = "t";
      key = "<C-k>";
      action = "<cmd>TmuxNavigateUp<CR>";
      options.desc = "Go to upper window/pane";
    }
    {
      mode = "t";
      key = "<C-l>";
      action = "<cmd>TmuxNavigateRight<CR>";
      options.desc = "Go to right window/pane";
    }
    # <Esc><Esc>: In AI buffers, toggle off; otherwise exit terminal mode
    {
      mode = "t";
      key = "<Esc><Esc>";
      action.__raw = ''
        function()
          local ft = vim.bo.filetype
          if ft == "claude-code" then
            require("claude-code").toggle()
          elseif ft == "opencode" then
            require("opencode").toggle()
          else
            vim.cmd("stopinsert")
          end
        end
      '';
      options.desc = "Exit terminal / Toggle AI";
    }
    {
      mode = "t";
      key = "jk";
      action = "<C-\\><C-n>";
      options.desc = "Exit terminal mode";
    }

    # =========================================================================
    # QUICK ACTIONS - Single leader key (most frequent)
    # =========================================================================
    {
      mode = "n";
      key = "<leader><space>";
      action.__raw = "function() Snacks.picker.files() end";
      options.desc = "Find files";
    }
    {
      mode = "n";
      key = "<leader>/";
      action.__raw = "function() Snacks.picker.grep() end";
      options.desc = "Grep";
    }
    {
      mode = "n";
      key = "<leader>e";
      action.__raw = "function() Snacks.explorer() end";
      options.desc = "Explorer";
    }
    {
      mode = "n";
      key = "<leader>E";
      action.__raw = "function() Snacks.explorer.open({cwd = vim.uv.cwd()}) end";
      options.desc = "Explorer (cwd)";
    }
    {
      mode = "n";
      key = "<leader>.";
      action.__raw = "function() Snacks.scratch() end";
      options.desc = "Scratch buffer";
    }
    {
      mode = "n";
      key = "<leader>,";
      action.__raw = "function() Snacks.picker.buffers() end";
      options.desc = "Switch buffer";
    }
    {
      mode = "n";
      key = "<leader>:";
      action.__raw = "function() Snacks.picker.command_history() end";
      options.desc = "Command history";
    }
    {
      mode = "n";
      key = "<leader>q";
      action = "<cmd>q<CR>";
      options.desc = "Quit";
    }

    # =========================================================================
    # AI TOOLS (<leader>a) - All AI assistants
    # =========================================================================
    # Design: Shallow entry, max 2-3 key depth
    #   <leader>a    → which-key menu (discover all)
    #   <leader>a{t} → direct tool toggle (2 keys)
    #   <leader>a{t}{action} → tool-specific actions (3 keys, high-value only)

    # Level 2: Direct tool toggles (most common actions)
    {
      mode = "n";
      key = "<leader>ac";
      action.__raw = "function() require('claude-code').toggle() end";
      options.desc = "Claude Code";
    }
    {
      mode = "n";
      key = "<leader>ao";
      action.__raw = "function() require('opencode').toggle() end";
      options.desc = "OpenCode";
    }
    {
      mode = "n";
      key = "<leader>ap";
      action = "<cmd>lua Konductor.copilot_cli_toggle()<CR>";
      options.desc = "Copilot CLI";
    }
    {
      mode = "n";
      key = "<leader>ax";
      action = "<cmd>lua Konductor.codex_cli_toggle()<CR>";
      options.desc = "Codex CLI";
    }
    {
      mode = "n";
      key = "<leader>ai";
      action = "<cmd>Copilot toggle<CR>";
      options.desc = "Copilot inline";
    }

    # Level 3: Claude Code actions (<leader>ac*)
    {
      mode = "n";
      key = "<leader>acr";
      action.__raw = "function() require('claude-code').toggle('resume') end";
      options.desc = "Resume";
    }
    {
      mode = "n";
      key = "<leader>ack";
      action.__raw = "function() require('claude-code').toggle('continue') end";
      options.desc = "Continue";
    }
    {
      mode = "n";
      key = "<leader>acv";
      action.__raw = "function() require('claude-code').toggle('verbose') end";
      options.desc = "Verbose";
    }

    # Level 3: OpenCode actions (<leader>ao*)
    {
      mode = "n";
      key = "<leader>aoa";
      action.__raw = "function() require('opencode').ask() end";
      options.desc = "Ask";
    }
    {
      mode = "n";
      key = "<leader>aos";
      action.__raw = "function() require('opencode').select() end";
      options.desc = "Select prompt";
    }
    {
      mode = "n";
      key = "<leader>aog";
      action.__raw = "function() require('opencode').command('agent.cycle') end";
      options.desc = "Cycle agent";
    }

    # Level 4: OpenCode prompts (<leader>aop*)
    {
      mode = "n";
      key = "<leader>aopr";
      action.__raw = "function() require('opencode').prompt('review') end";
      options.desc = "Review";
    }
    {
      mode = "v";
      key = "<leader>aopr";
      action.__raw = "function() require('opencode').prompt('review') end";
      options.desc = "Review";
    }
    {
      mode = "n";
      key = "<leader>aope";
      action.__raw = "function() require('opencode').prompt('explain') end";
      options.desc = "Explain";
    }
    {
      mode = "v";
      key = "<leader>aope";
      action.__raw = "function() require('opencode').prompt('explain') end";
      options.desc = "Explain";
    }
    {
      mode = "n";
      key = "<leader>aopd";
      action.__raw = "function() require('opencode').prompt('document') end";
      options.desc = "Document";
    }
    {
      mode = "v";
      key = "<leader>aopd";
      action.__raw = "function() require('opencode').prompt('document') end";
      options.desc = "Document";
    }
    {
      mode = "n";
      key = "<leader>aopf";
      action.__raw = "function() require('opencode').prompt('fix') end";
      options.desc = "Fix";
    }
    {
      mode = "n";
      key = "<leader>aopt";
      action.__raw = "function() require('opencode').prompt('test') end";
      options.desc = "Test";
    }
    {
      mode = "v";
      key = "<leader>aopt";
      action.__raw = "function() require('opencode').prompt('test') end";
      options.desc = "Test";
    }
    {
      mode = "n";
      key = "<leader>aopo";
      action.__raw = "function() require('opencode').prompt('optimize') end";
      options.desc = "Optimize";
    }
    {
      mode = "v";
      key = "<leader>aopo";
      action.__raw = "function() require('opencode').prompt('optimize') end";
      options.desc = "Optimize";
    }
    {
      mode = "n";
      key = "<leader>aopi";
      action.__raw = "function() require('opencode').prompt('implement') end";
      options.desc = "Implement";
    }
    {
      mode = "v";
      key = "<leader>aopi";
      action.__raw = "function() require('opencode').prompt('implement') end";
      options.desc = "Implement";
    }
    {
      mode = "n";
      key = "<leader>aopR";
      action.__raw = "function() require('opencode').prompt('refactor') end";
      options.desc = "Refactor";
    }
    {
      mode = "v";
      key = "<leader>aopR";
      action.__raw = "function() require('opencode').prompt('refactor') end";
      options.desc = "Refactor";
    }

    # Level 4: OpenCode session (<leader>aoss*)
    {
      mode = "n";
      key = "<leader>aossn";
      action.__raw = "function() require('opencode').command('session.new') end";
      options.desc = "New session";
    }
    {
      mode = "n";
      key = "<leader>aossl";
      action.__raw = "function() require('opencode').command('session.list') end";
      options.desc = "List sessions";
    }
    {
      mode = "n";
      key = "<leader>aosss";
      action.__raw = "function() require('opencode').command('session.share') end";
      options.desc = "Share";
    }
    {
      mode = "n";
      key = "<leader>aossu";
      action.__raw = "function() require('opencode').command('session.undo') end";
      options.desc = "Undo";
    }
    {
      mode = "n";
      key = "<leader>aossr";
      action.__raw = "function() require('opencode').command('session.redo') end";
      options.desc = "Redo";
    }

    # Level 3: Copilot inline actions (<leader>ai*)
    {
      mode = "n";
      key = "<leader>aie";
      action = "<cmd>Copilot enable<CR>";
      options.desc = "Enable";
    }
    {
      mode = "n";
      key = "<leader>aix";
      action = "<cmd>Copilot disable<CR>";
      options.desc = "Disable";
    }
    {
      mode = "n";
      key = "<leader>ais";
      action = "<cmd>Copilot status<CR>";
      options.desc = "Status";
    }

    # Operator motion - 'go' prefix for opencode (vim-native, dot-repeatable)
    # Example: goap (review paragraph), goiw (review word)
    {
      mode = "n";
      key = "go";
      action.__raw = "function() return require('opencode').operator() end";
      options.desc = "OpenCode operator";
      options.expr = true;
    }
    {
      mode = "v";
      key = "go";
      action.__raw = "function() require('opencode').prompt('review') end";
      options.desc = "OpenCode review";
    }

    # =========================================================================
    # REST (<leader>r) - HTTP client for .http files
    # =========================================================================
    {
      mode = "n";
      key = "<leader>rr";
      action = "<Plug>RestNvim";
      options.desc = "Run request";
    }
    {
      mode = "n";
      key = "<leader>rp";
      action = "<Plug>RestNvimPreview";
      options.desc = "Preview request";
    }
    {
      mode = "n";
      key = "<leader>rl";
      action = "<Plug>RestNvimLast";
      options.desc = "Rerun last request";
    }

    # =========================================================================
    # LSP (<leader>l) - Language intelligence
    # =========================================================================
    {
      mode = "n";
      key = "<leader>la";
      action.__raw = "vim.lsp.buf.code_action";
      options.desc = "Code action";
    }
    {
      mode = "n";
      key = "<leader>lr";
      action.__raw = "vim.lsp.buf.rename";
      options.desc = "Rename symbol";
    }
    {
      mode = "n";
      key = "<leader>lf";
      action.__raw = "function() require('conform').format() end";
      options.desc = "Format";
    }
    {
      mode = "n";
      key = "<leader>li";
      action = "<cmd>LspInfo<CR>";
      options.desc = "LSP info";
    }
    {
      mode = "n";
      key = "<leader>lR";
      action = "<cmd>LspRestart<CR>";
      options.desc = "LSP restart";
    }
    {
      mode = "n";
      key = "<leader>ls";
      action.__raw = "function() Snacks.picker.lsp_symbols() end";
      options.desc = "Document symbols";
    }
    {
      mode = "n";
      key = "<leader>lS";
      action.__raw = "function() Snacks.picker.lsp_workspace_symbols() end";
      options.desc = "Workspace symbols";
    }
    {
      mode = "n";
      key = "<leader>ld";
      action.__raw = "function() Snacks.picker.diagnostics() end";
      options.desc = "Diagnostics";
    }
    {
      mode = "n";
      key = "<leader>lD";
      action.__raw = "function() Snacks.picker.diagnostics_buffer() end";
      options.desc = "Buffer diagnostics";
    }
    {
      mode = "n";
      key = "<leader>lh";
      action.__raw = "function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end";
      options.desc = "Toggle inlay hints";
    }
    {
      mode = "n";
      key = "<leader>lF";
      action.__raw = "function() Snacks.rename.rename_file() end";
      options.desc = "Rename file";
    }

    # LSP goto (no leader - direct navigation)
    {
      mode = "n";
      key = "gd";
      action.__raw = "function() Snacks.picker.lsp_definitions() end";
      options.desc = "Goto definition";
    }
    {
      mode = "n";
      key = "gr";
      action.__raw = "function() Snacks.picker.lsp_references() end";
      options.desc = "References";
    }
    {
      mode = "n";
      key = "gI";
      action.__raw = "function() Snacks.picker.lsp_implementations() end";
      options.desc = "Implementations";
    }
    {
      mode = "n";
      key = "gy";
      action.__raw = "function() Snacks.picker.lsp_type_definitions() end";
      options.desc = "Type definition";
    }
    {
      mode = "n";
      key = "gD";
      action.__raw = "vim.lsp.buf.declaration";
      options.desc = "Goto declaration";
    }
    {
      mode = "n";
      key = "K";
      action.__raw = "vim.lsp.buf.hover";
      options.desc = "Hover docs";
    }
    {
      mode = "n";
      key = "gK";
      action.__raw = "vim.lsp.buf.signature_help";
      options.desc = "Signature help";
    }

    # =========================================================================
    # FIND (<leader>f) - File operations
    # =========================================================================
    {
      mode = "n";
      key = "<leader>ff";
      action.__raw = "function() Snacks.picker.files() end";
      options.desc = "Find files";
    }
    {
      mode = "n";
      key = "<leader>fg";
      action.__raw = "function() Snacks.picker.git_files() end";
      options.desc = "Git files";
    }
    {
      mode = "n";
      key = "<leader>fr";
      action.__raw = "function() Snacks.picker.recent() end";
      options.desc = "Recent files";
    }
    {
      mode = "n";
      key = "<leader>fb";
      action.__raw = "function() Snacks.picker.buffers() end";
      options.desc = "Buffers";
    }
    {
      mode = "n";
      key = "<leader>fc";
      action.__raw = "function() Snacks.picker.files({cwd = vim.fn.stdpath('config')}) end";
      options.desc = "Config files";
    }
    {
      mode = "n";
      key = "<leader>fp";
      action.__raw = "function() Snacks.picker.projects() end";
      options.desc = "Projects";
    }

    # =========================================================================
    # SEARCH (<leader>s) - Search and discovery
    # =========================================================================
    {
      mode = "n";
      key = "<leader>sg";
      action.__raw = "function() Snacks.picker.grep() end";
      options.desc = "Grep";
    }
    {
      mode = "n";
      key = "<leader>sw";
      action.__raw = "function() Snacks.picker.grep_word() end";
      options.desc = "Grep word";
    }
    {
      mode = "v";
      key = "<leader>sw";
      action.__raw = "function() Snacks.picker.grep_word() end";
      options.desc = "Grep selection";
    }
    {
      mode = "n";
      key = "<leader>sb";
      action.__raw = "function() Snacks.picker.lines() end";
      options.desc = "Buffer lines";
    }
    {
      mode = "n";
      key = "<leader>sB";
      action.__raw = "function() Snacks.picker.grep_buffers() end";
      options.desc = "Grep buffers";
    }
    {
      mode = "n";
      key = "<leader>sh";
      action.__raw = "function() Snacks.picker.help() end";
      options.desc = "Help pages";
    }
    {
      mode = "n";
      key = "<leader>sk";
      action.__raw = "function() Snacks.picker.keymaps() end";
      options.desc = "Keymaps";
    }
    {
      mode = "n";
      key = "<leader>sc";
      action.__raw = "function() Snacks.picker.commands() end";
      options.desc = "Commands";
    }
    {
      mode = "n";
      key = "<leader>sC";
      action.__raw = "function() Snacks.picker.colorschemes() end";
      options.desc = "Colorschemes";
    }
    {
      mode = "n";
      key = "<leader>sH";
      action.__raw = "function() Snacks.picker.highlights() end";
      options.desc = "Highlights";
    }
    {
      mode = "n";
      key = "<leader>sm";
      action.__raw = "function() Snacks.picker.marks() end";
      options.desc = "Marks";
    }
    {
      mode = "n";
      key = "<leader>sj";
      action.__raw = "function() Snacks.picker.jumps() end";
      options.desc = "Jumps";
    }
    {
      mode = "n";
      key = "<leader>sr";
      action.__raw = "function() Snacks.picker.resume() end";
      options.desc = "Resume search";
    }
    {
      mode = "n";
      key = "<leader>sn";
      action.__raw = "function() Snacks.picker.notifications() end";
      options.desc = "Notifications";
    }
    {
      mode = "n";
      key = "<leader>s/";
      action.__raw = "function() Snacks.picker.search_history() end";
      options.desc = "Search history";
    }

    # =========================================================================
    # BUFFERS (<leader>b) - Buffer management
    # =========================================================================
    {
      mode = "n";
      key = "<S-h>";
      action = "<cmd>BufferLineCyclePrev<CR>";
      options.desc = "Prev buffer";
    }
    {
      mode = "n";
      key = "<S-l>";
      action = "<cmd>BufferLineCycleNext<CR>";
      options.desc = "Next buffer";
    }
    {
      mode = "n";
      key = "[b";
      action = "<cmd>BufferLineCyclePrev<CR>";
      options.desc = "Prev buffer";
    }
    {
      mode = "n";
      key = "]b";
      action = "<cmd>BufferLineCycleNext<CR>";
      options.desc = "Next buffer";
    }
    {
      mode = "n";
      key = "<leader>bb";
      action.__raw = "function() Snacks.picker.buffers() end";
      options.desc = "Switch buffer";
    }
    {
      mode = "n";
      key = "<leader>bd";
      action.__raw = "function() Snacks.bufdelete() end";
      options.desc = "Delete buffer";
    }
    {
      mode = "n";
      key = "<leader>bD";
      action.__raw = "function() Snacks.bufdelete.other() end";
      options.desc = "Delete other buffers";
    }
    {
      mode = "n";
      key = "<leader>bp";
      action = "<cmd>BufferLineTogglePin<CR>";
      options.desc = "Toggle pin";
    }
    {
      mode = "n";
      key = "<leader>bP";
      action = "<cmd>BufferLineGroupClose ungrouped<CR>";
      options.desc = "Close unpinned";
    }
    {
      mode = "n";
      key = "<leader>bo";
      action = "<cmd>BufferLineCloseOthers<CR>";
      options.desc = "Close others";
    }
    {
      mode = "n";
      key = "<leader>br";
      action = "<cmd>BufferLineCloseRight<CR>";
      options.desc = "Close right";
    }
    {
      mode = "n";
      key = "<leader>bl";
      action = "<cmd>BufferLineCloseLeft<CR>";
      options.desc = "Close left";
    }
    {
      mode = "n";
      key = "<leader>b1";
      action = "<cmd>BufferLineGoToBuffer 1<CR>";
      options.desc = "Buffer 1";
    }
    {
      mode = "n";
      key = "<leader>b2";
      action = "<cmd>BufferLineGoToBuffer 2<CR>";
      options.desc = "Buffer 2";
    }
    {
      mode = "n";
      key = "<leader>b3";
      action = "<cmd>BufferLineGoToBuffer 3<CR>";
      options.desc = "Buffer 3";
    }
    {
      mode = "n";
      key = "<leader>b4";
      action = "<cmd>BufferLineGoToBuffer 4<CR>";
      options.desc = "Buffer 4";
    }
    {
      mode = "n";
      key = "<leader>b5";
      action = "<cmd>BufferLineGoToBuffer 5<CR>";
      options.desc = "Buffer 5";
    }

    # =========================================================================
    # GIT (<leader>g) - Version control
    # =========================================================================
    {
      mode = "n";
      key = "<leader>gg";
      action.__raw = "function() Snacks.lazygit() end";
      options.desc = "LazyGit";
    }
    {
      mode = "n";
      key = "<leader>gG";
      action.__raw = "function() Snacks.lazygit.log() end";
      options.desc = "LazyGit log";
    }
    {
      mode = "n";
      key = "<leader>gf";
      action.__raw = "function() Snacks.lazygit.log_file() end";
      options.desc = "File history";
    }
    {
      mode = "n";
      key = "<leader>gl";
      action.__raw = "function() Snacks.git.blame_line() end";
      options.desc = "Blame line";
    }
    {
      mode = "n";
      key = "<leader>gB";
      action.__raw = "function() Snacks.gitbrowse() end";
      options.desc = "Browse repo";
    }
    {
      mode = "n";
      key = "<leader>gd";
      action = "<cmd>DiffviewOpen<CR>";
      options.desc = "Diff view";
    }
    {
      mode = "n";
      key = "<leader>gD";
      action = "<cmd>DiffviewClose<CR>";
      options.desc = "Close diff";
    }

    # Hunk operations
    {
      mode = "n";
      key = "]h";
      action.__raw = "function() require('gitsigns').nav_hunk('next') end";
      options.desc = "Next hunk";
    }
    {
      mode = "n";
      key = "[h";
      action.__raw = "function() require('gitsigns').nav_hunk('prev') end";
      options.desc = "Prev hunk";
    }
    {
      mode = "n";
      key = "<leader>ghs";
      action = "<cmd>Gitsigns stage_hunk<CR>";
      options.desc = "Stage hunk";
    }
    {
      mode = "v";
      key = "<leader>ghs";
      action = "<cmd>Gitsigns stage_hunk<CR>";
      options.desc = "Stage hunk";
    }
    {
      mode = "n";
      key = "<leader>ghr";
      action = "<cmd>Gitsigns reset_hunk<CR>";
      options.desc = "Reset hunk";
    }
    {
      mode = "v";
      key = "<leader>ghr";
      action = "<cmd>Gitsigns reset_hunk<CR>";
      options.desc = "Reset hunk";
    }
    {
      mode = "n";
      key = "<leader>ghp";
      action = "<cmd>Gitsigns preview_hunk<CR>";
      options.desc = "Preview hunk";
    }
    {
      mode = "n";
      key = "<leader>ghb";
      action = "<cmd>Gitsigns blame_line<CR>";
      options.desc = "Blame line";
    }
    {
      mode = "n";
      key = "<leader>ghS";
      action = "<cmd>Gitsigns stage_buffer<CR>";
      options.desc = "Stage buffer";
    }
    {
      mode = "n";
      key = "<leader>ghR";
      action = "<cmd>Gitsigns reset_buffer<CR>";
      options.desc = "Reset buffer";
    }

    # =========================================================================
    # TERMINAL (<leader>t) - Terminal operations (opens BOTTOM)
    # =========================================================================
    {
      mode = "n";
      key = "<leader>tt";
      action.__raw = "function() Snacks.terminal() end";
      options.desc = "Toggle terminal";
    }
    {
      mode = "n";
      key = "<leader>tf";
      action.__raw = "function() Snacks.terminal(nil, {win = {position = 'float'}}) end";
      options.desc = "Float terminal";
    }
    {
      mode = "n";
      key = "<leader>th";
      action.__raw = "function() Snacks.terminal(nil, {win = {position = 'bottom', height = 0.4}}) end";
      options.desc = "Large terminal";
    }
    {
      mode = "n";
      key = "<leader>tv";
      action.__raw = "function() Snacks.terminal(nil, {win = {position = 'right', width = 0.4}}) end";
      options.desc = "Side terminal";
    }
    {
      mode = "n";
      key = "<C-/>";
      action.__raw = "function() Snacks.terminal() end";
      options.desc = "Terminal";
    }
    {
      mode = "t";
      key = "<C-/>";
      action = "<cmd>close<CR>";
      options.desc = "Hide terminal";
    }
    # Custom terminals (via Konductor namespace in extraConfig.nix)
    {
      mode = "n";
      key = "<leader>tg";
      action.__raw = "function() Snacks.lazygit() end";
      options.desc = "LazyGit";
    }
    {
      mode = "n";
      key = "<leader>tb";
      action = "<cmd>lua Konductor.btop_toggle()<CR>";
      options.desc = "Btop monitor";
    }
    {
      mode = "n";
      key = "<leader>tp";
      action = "<cmd>lua Konductor.python_toggle()<CR>";
      options.desc = "Python REPL";
    }
    {
      mode = "n";
      key = "<leader>tn";
      action = "<cmd>lua Konductor.node_toggle()<CR>";
      options.desc = "Node REPL";
    }

    # =========================================================================
    # WINDOW (<leader>w) - Window/split management
    # =========================================================================
    # Quick focus (matches layout: e=left, v=right, t=bottom)
    {
      mode = "n";
      key = "<leader>we";
      action.__raw = "function() Snacks.explorer() end";
      options.desc = "Focus explorer (left)";
    }
    {
      mode = "n";
      key = "<leader>wv";
      action.__raw = "function() require('claude-code').toggle() end";
      options.desc = "Focus vibe (right)";
    }
    {
      mode = "n";
      key = "<leader>wt";
      action.__raw = "function() Snacks.terminal() end";
      options.desc = "Focus terminal (bottom)";
    }

    # Directional focus
    {
      mode = "n";
      key = "<leader>wh";
      action = "<C-w>h";
      options.desc = "Focus left";
    }
    {
      mode = "n";
      key = "<leader>wj";
      action = "<C-w>j";
      options.desc = "Focus down";
    }
    {
      mode = "n";
      key = "<leader>wk";
      action = "<C-w>k";
      options.desc = "Focus up";
    }
    {
      mode = "n";
      key = "<leader>wl";
      action = "<C-w>l";
      options.desc = "Focus right";
    }

    # Split management
    {
      mode = "n";
      key = "<leader>ws";
      action = "<cmd>split<CR>";
      options.desc = "Split horizontal";
    }
    {
      mode = "n";
      key = "<leader>wS";
      action = "<cmd>vsplit<CR>";
      options.desc = "Split vertical";
    }
    {
      mode = "n";
      key = "<leader>wc";
      action = "<cmd>close<CR>";
      options.desc = "Close window";
    }
    {
      mode = "n";
      key = "<leader>wo";
      action = "<cmd>only<CR>";
      options.desc = "Close other windows";
    }
    {
      mode = "n";
      key = "<leader>w=";
      action = "<C-w>=";
      options.desc = "Balance windows";
    }
    {
      mode = "n";
      key = "<leader>wm";
      action.__raw = "function() Snacks.zen.zoom() end";
      options.desc = "Maximize/zoom";
    }

    # =========================================================================
    # DIAGNOSTICS (<leader>x) - Trouble & issues
    # =========================================================================
    {
      mode = "n";
      key = "<leader>xx";
      action = "<cmd>Trouble diagnostics toggle<CR>";
      options.desc = "Diagnostics";
    }
    {
      mode = "n";
      key = "<leader>xX";
      action = "<cmd>Trouble diagnostics toggle filter.buf=0<CR>";
      options.desc = "Buffer diagnostics";
    }
    {
      mode = "n";
      key = "<leader>xs";
      action = "<cmd>Trouble symbols toggle<CR>";
      options.desc = "Symbols";
    }
    {
      mode = "n";
      key = "<leader>xq";
      action = "<cmd>Trouble qflist toggle<CR>";
      options.desc = "Quickfix";
    }
    {
      mode = "n";
      key = "<leader>xl";
      action = "<cmd>Trouble loclist toggle<CR>";
      options.desc = "Location list";
    }
    {
      mode = "n";
      key = "<leader>xt";
      action = "<cmd>Trouble todo toggle<CR>";
      options.desc = "TODOs";
    }
    {
      mode = "n";
      key = "]x";
      action.__raw = "function() require('trouble').next({skip_groups = true, jump = true}) end";
      options.desc = "Next trouble";
    }
    {
      mode = "n";
      key = "[x";
      action.__raw = "function() require('trouble').prev({skip_groups = true, jump = true}) end";
      options.desc = "Prev trouble";
    }

    # =========================================================================
    # MARKDOWN (<leader>m) - Documentation
    # =========================================================================
    # render-markdown.nvim - live in-editor rendering (normal mode)
    {
      mode = "n";
      key = "<leader>mt";
      action = "<cmd>RenderMarkdown toggle<CR>";
      options.desc = "Toggle render";
    }
    {
      mode = "n";
      key = "<leader>me";
      action = "<cmd>RenderMarkdown expand<CR>";
      options.desc = "Expand anti-conceal";
    }
    {
      mode = "n";
      key = "<leader>mc";
      action = "<cmd>RenderMarkdown contract<CR>";
      options.desc = "Contract anti-conceal";
    }
    # markdown-preview - browser-based preview
    {
      mode = "n";
      key = "<leader>mp";
      action = "<cmd>MarkdownPreviewToggle<CR>";
      options.desc = "Browser preview";
    }
    {
      mode = "n";
      key = "<leader>ms";
      action = "<cmd>MarkdownPreview<CR>";
      options.desc = "Start browser";
    }
    {
      mode = "n";
      key = "<leader>mx";
      action = "<cmd>MarkdownPreviewStop<CR>";
      options.desc = "Stop browser";
    }

    # =========================================================================
    # SESSION (<leader>q) - Session & quit
    # =========================================================================
    {
      mode = "n";
      key = "<leader>qq";
      action = "<cmd>qa<CR>";
      options.desc = "Quit all";
    }
    {
      mode = "n";
      key = "<leader>qQ";
      action = "<cmd>qa!<CR>";
      options.desc = "Quit all (force)";
    }
    {
      mode = "n";
      key = "<leader>qs";
      action.__raw = "function() require('persistence').load() end";
      options.desc = "Restore session";
    }
    {
      mode = "n";
      key = "<leader>ql";
      action.__raw = "function() require('persistence').load({last = true}) end";
      options.desc = "Restore last";
    }
    {
      mode = "n";
      key = "<leader>qd";
      action.__raw = "function() require('persistence').stop() end";
      options.desc = "Don't save session";
    }
    {
      mode = "n";
      key = "<leader>qS";
      action.__raw = "function() require('persistence').select() end";
      options.desc = "Select session";
    }

    # =========================================================================
    # UI TOGGLES (<leader>u) - Interface customization
    # =========================================================================
    {
      mode = "n";
      key = "<leader>un";
      action.__raw = "function() Snacks.notifier.hide() end";
      options.desc = "Dismiss notifications";
    }
    {
      mode = "n";
      key = "<leader>uN";
      action.__raw = "function() Snacks.notifier.show_history() end";
      options.desc = "Notification history";
    }
    {
      mode = "n";
      key = "<leader>uz";
      action.__raw = "function() Snacks.zen() end";
      options.desc = "Zen mode";
    }
    {
      mode = "n";
      key = "<leader>uZ";
      action.__raw = "function() Snacks.zen.zoom() end";
      options.desc = "Zoom";
    }
    {
      mode = "n";
      key = "<leader>ud";
      action.__raw = "function() Snacks.dim() end";
      options.desc = "Dim mode";
    }
    {
      mode = "n";
      key = "<leader>us";
      action.__raw = "function() Snacks.toggle.option('spell'):toggle() end";
      options.desc = "Toggle spell";
    }
    {
      mode = "n";
      key = "<leader>uw";
      action.__raw = "function() Snacks.toggle.option('wrap'):toggle() end";
      options.desc = "Toggle wrap";
    }
    {
      mode = "n";
      key = "<leader>ul";
      action.__raw = "function() Snacks.toggle.line_number():toggle() end";
      options.desc = "Toggle line numbers";
    }
    {
      mode = "n";
      key = "<leader>uL";
      action.__raw = "function() Snacks.toggle.option('relativenumber'):toggle() end";
      options.desc = "Toggle relative numbers";
    }
    {
      mode = "n";
      key = "<leader>uD";
      action.__raw = "function() Snacks.toggle.diagnostics():toggle() end";
      options.desc = "Toggle diagnostics";
    }
    {
      mode = "n";
      key = "<leader>uh";
      action.__raw = "function() Snacks.toggle.inlay_hints():toggle() end";
      options.desc = "Toggle inlay hints";
    }
    {
      mode = "n";
      key = "<leader>uT";
      action.__raw = "function() Snacks.toggle.treesitter():toggle() end";
      options.desc = "Toggle treesitter";
    }
    {
      mode = "n";
      key = "<leader>uc";
      action.__raw = "function() Snacks.toggle.option('conceallevel', {off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2}):toggle() end";
      options.desc = "Toggle conceal";
    }

    # =========================================================================
    # UTILITIES
    # =========================================================================
    {
      mode = "n";
      key = "<leader>S";
      action.__raw = "function() Snacks.scratch.select() end";
      options.desc = "Select scratch";
    }
    {
      mode = "n";
      key = "]]";
      action.__raw = "function() Snacks.words.jump(vim.v.count1) end";
      options.desc = "Next reference";
    }
    {
      mode = "n";
      key = "[[";
      action.__raw = "function() Snacks.words.jump(-vim.v.count1) end";
      options.desc = "Prev reference";
    }

    # Comments (gcc/gc are native, these are convenient alternatives)
    {
      mode = "n";
      key = "<leader>gc";
      action = "gcc";
      options.desc = "Comment line";
      options.remap = true;
    }
    {
      mode = "v";
      key = "<leader>gc";
      action = "gc";
      options.desc = "Comment selection";
      options.remap = true;
    }
  ];
}
