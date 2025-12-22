# src/programs/neovim/keymaps.nix
# All keybindings following LazyVim conventions
{ lib }:

{
  keymaps = [
    # =========================================================================
    # GENERAL
    # =========================================================================
    { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<CR>"; options.desc = "Clear search"; }

    # Better window navigation
    { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options.desc = "Go to left window"; }
    { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options.desc = "Go to lower window"; }
    { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options.desc = "Go to upper window"; }
    { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options.desc = "Go to right window"; }

    # Resize windows
    { mode = "n"; key = "<C-Up>"; action = "<cmd>resize +2<CR>"; options.desc = "Increase height"; }
    { mode = "n"; key = "<C-Down>"; action = "<cmd>resize -2<CR>"; options.desc = "Decrease height"; }
    { mode = "n"; key = "<C-Left>"; action = "<cmd>vertical resize -2<CR>"; options.desc = "Decrease width"; }
    { mode = "n"; key = "<C-Right>"; action = "<cmd>vertical resize +2<CR>"; options.desc = "Increase width"; }

    # Move lines
    { mode = "n"; key = "<A-j>"; action = "<cmd>m .+1<CR>=="; options.desc = "Move line down"; }
    { mode = "n"; key = "<A-k>"; action = "<cmd>m .-2<CR>=="; options.desc = "Move line up"; }
    { mode = "v"; key = "<A-j>"; action = ":m '>+1<CR>gv=gv"; options.desc = "Move selection down"; }
    { mode = "v"; key = "<A-k>"; action = ":m '<-2<CR>gv=gv"; options.desc = "Move selection up"; }

    # Better indenting
    { mode = "v"; key = "<"; action = "<gv"; }
    { mode = "v"; key = ">"; action = ">gv"; }

    # =========================================================================
    # BUFFERS (Snacks.bufdelete + Bufferline)
    # =========================================================================
    { mode = "n"; key = "<S-h>"; action = "<cmd>BufferLineCyclePrev<CR>"; options.desc = "Prev buffer"; }
    { mode = "n"; key = "<S-l>"; action = "<cmd>BufferLineCycleNext<CR>"; options.desc = "Next buffer"; }
    { mode = "n"; key = "[b"; action = "<cmd>BufferLineCyclePrev<CR>"; options.desc = "Prev buffer"; }
    { mode = "n"; key = "]b"; action = "<cmd>BufferLineCycleNext<CR>"; options.desc = "Next buffer"; }
    { mode = "n"; key = "<leader>bd"; action.__raw = "function() Snacks.bufdelete() end"; options.desc = "Delete buffer"; }
    { mode = "n"; key = "<leader>bD"; action.__raw = "function() Snacks.bufdelete.other() end"; options.desc = "Delete other buffers"; }
    { mode = "n"; key = "<leader>bp"; action = "<cmd>BufferLineTogglePin<CR>"; options.desc = "Toggle pin"; }
    { mode = "n"; key = "<leader>bo"; action = "<cmd>BufferLineCloseOthers<CR>"; options.desc = "Close others"; }

    # =========================================================================
    # FIND (Snacks.picker)
    # =========================================================================
    { mode = "n"; key = "<leader><space>"; action.__raw = "function() Snacks.picker.files() end"; options.desc = "Find files"; }
    { mode = "n"; key = "<leader>ff"; action.__raw = "function() Snacks.picker.files() end"; options.desc = "Find files"; }
    { mode = "n"; key = "<leader>fg"; action.__raw = "function() Snacks.picker.git_files() end"; options.desc = "Find git files"; }
    { mode = "n"; key = "<leader>fr"; action.__raw = "function() Snacks.picker.recent() end"; options.desc = "Recent files"; }
    { mode = "n"; key = "<leader>fb"; action.__raw = "function() Snacks.picker.buffers() end"; options.desc = "Buffers"; }

    # =========================================================================
    # SEARCH (Snacks.picker)
    # =========================================================================
    { mode = "n"; key = "<leader>/"; action.__raw = "function() Snacks.picker.grep() end"; options.desc = "Grep"; }
    { mode = "n"; key = "<leader>sg"; action.__raw = "function() Snacks.picker.grep() end"; options.desc = "Grep"; }
    { mode = "n"; key = "<leader>sw"; action.__raw = "function() Snacks.picker.grep_word() end"; options.desc = "Grep word"; }
    { mode = "n"; key = "<leader>sh"; action.__raw = "function() Snacks.picker.help() end"; options.desc = "Help pages"; }
    { mode = "n"; key = "<leader>sk"; action.__raw = "function() Snacks.picker.keymaps() end"; options.desc = "Keymaps"; }
    { mode = "n"; key = "<leader>sc"; action.__raw = "function() Snacks.picker.commands() end"; options.desc = "Commands"; }
    { mode = "n"; key = "<leader>sC"; action.__raw = "function() Snacks.picker.colorschemes() end"; options.desc = "Colorschemes"; }
    { mode = "n"; key = "<leader>sd"; action.__raw = "function() Snacks.picker.diagnostics() end"; options.desc = "Diagnostics"; }
    { mode = "n"; key = "<leader>sD"; action.__raw = "function() Snacks.picker.diagnostics_buffer() end"; options.desc = "Buffer diagnostics"; }
    { mode = "n"; key = "<leader>sn"; action.__raw = "function() Snacks.picker.notifications() end"; options.desc = "Notifications"; }

    # =========================================================================
    # EXPLORER (Snacks.explorer)
    # =========================================================================
    { mode = "n"; key = "<leader>e"; action.__raw = "function() Snacks.explorer() end"; options.desc = "Explorer"; }
    { mode = "n"; key = "<leader>E"; action.__raw = "function() Snacks.explorer.open({cwd = vim.uv.cwd()}) end"; options.desc = "Explorer (cwd)"; }

    # =========================================================================
    # TERMINAL (Snacks.terminal)
    # =========================================================================
    { mode = "n"; key = "<leader>ft"; action.__raw = "function() Snacks.terminal() end"; options.desc = "Terminal"; }
    { mode = "n"; key = "<C-/>"; action.__raw = "function() Snacks.terminal() end"; options.desc = "Terminal"; }
    { mode = "t"; key = "<C-/>"; action = "<cmd>close<CR>"; options.desc = "Hide terminal"; }

    # =========================================================================
    # GIT (Snacks.lazygit + gitsigns)
    # =========================================================================
    { mode = "n"; key = "<leader>gg"; action.__raw = "function() Snacks.lazygit() end"; options.desc = "LazyGit"; }
    { mode = "n"; key = "<leader>gG"; action.__raw = "function() Snacks.lazygit.log() end"; options.desc = "LazyGit log"; }
    { mode = "n"; key = "<leader>gf"; action.__raw = "function() Snacks.lazygit.log_file() end"; options.desc = "LazyGit file log"; }
    { mode = "n"; key = "<leader>gb"; action.__raw = "function() Snacks.gitbrowse() end"; options.desc = "Git browse"; }
    { mode = "n"; key = "]h"; action.__raw = "function() require('gitsigns').nav_hunk('next') end"; options.desc = "Next hunk"; }
    { mode = "n"; key = "[h"; action.__raw = "function() require('gitsigns').nav_hunk('prev') end"; options.desc = "Prev hunk"; }
    { mode = "n"; key = "<leader>ghs"; action = "<cmd>Gitsigns stage_hunk<CR>"; options.desc = "Stage hunk"; }
    { mode = "n"; key = "<leader>ghr"; action = "<cmd>Gitsigns reset_hunk<CR>"; options.desc = "Reset hunk"; }
    { mode = "n"; key = "<leader>ghp"; action = "<cmd>Gitsigns preview_hunk<CR>"; options.desc = "Preview hunk"; }
    { mode = "n"; key = "<leader>ghb"; action = "<cmd>Gitsigns blame_line<CR>"; options.desc = "Blame line"; }
    { mode = "n"; key = "<leader>gd"; action = "<cmd>DiffviewOpen<CR>"; options.desc = "Diffview"; }

    # =========================================================================
    # CODE (LSP)
    # =========================================================================
    { mode = "n"; key = "gd"; action.__raw = "function() Snacks.picker.lsp_definitions() end"; options.desc = "Goto definition"; }
    { mode = "n"; key = "gr"; action.__raw = "function() Snacks.picker.lsp_references() end"; options.desc = "References"; }
    { mode = "n"; key = "gI"; action.__raw = "function() Snacks.picker.lsp_implementations() end"; options.desc = "Implementations"; }
    { mode = "n"; key = "gy"; action.__raw = "function() Snacks.picker.lsp_type_definitions() end"; options.desc = "Type definition"; }
    { mode = "n"; key = "gD"; action.__raw = "vim.lsp.buf.declaration"; options.desc = "Goto declaration"; }
    { mode = "n"; key = "K"; action.__raw = "vim.lsp.buf.hover"; options.desc = "Hover"; }
    { mode = "n"; key = "gK"; action.__raw = "vim.lsp.buf.signature_help"; options.desc = "Signature help"; }
    { mode = "n"; key = "<leader>ca"; action.__raw = "vim.lsp.buf.code_action"; options.desc = "Code action"; }
    { mode = "n"; key = "<leader>cr"; action.__raw = "vim.lsp.buf.rename"; options.desc = "Rename"; }
    { mode = "n"; key = "<leader>cf"; action.__raw = "function() require('conform').format() end"; options.desc = "Format"; }
    { mode = "n"; key = "<leader>cl"; action = "<cmd>LspInfo<CR>"; options.desc = "LSP info"; }
    { mode = "n"; key = "<leader>cR"; action.__raw = "function() Snacks.rename.rename_file() end"; options.desc = "Rename file"; }
    { mode = "n"; key = "<leader>ss"; action.__raw = "function() Snacks.picker.lsp_symbols() end"; options.desc = "Symbols"; }
    { mode = "n"; key = "<leader>sS"; action.__raw = "function() Snacks.picker.lsp_workspace_symbols() end"; options.desc = "Workspace symbols"; }

    # =========================================================================
    # DIAGNOSTICS (Trouble)
    # =========================================================================
    { mode = "n"; key = "<leader>xx"; action = "<cmd>Trouble diagnostics toggle<CR>"; options.desc = "Diagnostics"; }
    { mode = "n"; key = "<leader>xX"; action = "<cmd>Trouble diagnostics toggle filter.buf=0<CR>"; options.desc = "Buffer diagnostics"; }
    { mode = "n"; key = "<leader>xs"; action = "<cmd>Trouble symbols toggle<CR>"; options.desc = "Symbols"; }
    { mode = "n"; key = "<leader>xq"; action = "<cmd>Trouble qflist toggle<CR>"; options.desc = "Quickfix"; }
    { mode = "n"; key = "<leader>xl"; action = "<cmd>Trouble loclist toggle<CR>"; options.desc = "Location list"; }
    { mode = "n"; key = "<leader>xt"; action = "<cmd>Trouble todo toggle<CR>"; options.desc = "TODOs"; }
    { mode = "n"; key = "]x"; action.__raw = "function() require('trouble').next({skip_groups = true, jump = true}) end"; options.desc = "Next trouble"; }
    { mode = "n"; key = "[x"; action.__raw = "function() require('trouble').prev({skip_groups = true, jump = true}) end"; options.desc = "Prev trouble"; }

    # =========================================================================
    # SESSION (persistence.nvim)
    # =========================================================================
    { mode = "n"; key = "<leader>qs"; action.__raw = "function() require('persistence').load() end"; options.desc = "Restore session"; }
    { mode = "n"; key = "<leader>ql"; action.__raw = "function() require('persistence').load({last = true}) end"; options.desc = "Restore last"; }
    { mode = "n"; key = "<leader>qd"; action.__raw = "function() require('persistence').stop() end"; options.desc = "Stop session"; }
    { mode = "n"; key = "<leader>qS"; action.__raw = "function() require('persistence').select() end"; options.desc = "Select session"; }

    # =========================================================================
    # UI TOGGLES (Snacks.toggle)
    # =========================================================================
    { mode = "n"; key = "<leader>un"; action.__raw = "function() Snacks.notifier.hide() end"; options.desc = "Dismiss notifications"; }
    { mode = "n"; key = "<leader>uz"; action.__raw = "function() Snacks.zen() end"; options.desc = "Zen mode"; }
    { mode = "n"; key = "<leader>uZ"; action.__raw = "function() Snacks.zen.zoom() end"; options.desc = "Zoom"; }
    { mode = "n"; key = "<leader>ud"; action.__raw = "function() Snacks.dim() end"; options.desc = "Dim mode"; }
    { mode = "n"; key = "<leader>us"; action.__raw = "function() Snacks.toggle.option('spell'):toggle() end"; options.desc = "Toggle spell"; }
    { mode = "n"; key = "<leader>uw"; action.__raw = "function() Snacks.toggle.option('wrap'):toggle() end"; options.desc = "Toggle wrap"; }
    { mode = "n"; key = "<leader>ul"; action.__raw = "function() Snacks.toggle.line_number():toggle() end"; options.desc = "Toggle line numbers"; }
    { mode = "n"; key = "<leader>uL"; action.__raw = "function() Snacks.toggle.option('relativenumber'):toggle() end"; options.desc = "Toggle relative numbers"; }
    { mode = "n"; key = "<leader>uD"; action.__raw = "function() Snacks.toggle.diagnostics():toggle() end"; options.desc = "Toggle diagnostics"; }
    { mode = "n"; key = "<leader>uh"; action.__raw = "function() Snacks.toggle.inlay_hints():toggle() end"; options.desc = "Toggle inlay hints"; }
    { mode = "n"; key = "<leader>uT"; action.__raw = "function() Snacks.toggle.treesitter():toggle() end"; options.desc = "Toggle treesitter"; }

    # =========================================================================
    # UTILITIES
    # =========================================================================
    { mode = "n"; key = "<leader>."; action.__raw = "function() Snacks.scratch() end"; options.desc = "Scratch buffer"; }
    { mode = "n"; key = "<leader>S"; action.__raw = "function() Snacks.scratch.select() end"; options.desc = "Select scratch"; }
    { mode = "n"; key = "]]"; action.__raw = "function() Snacks.words.jump(vim.v.count1) end"; options.desc = "Next reference"; }
    { mode = "n"; key = "[["; action.__raw = "function() Snacks.words.jump(-vim.v.count1) end"; options.desc = "Prev reference"; }
  ];
}
