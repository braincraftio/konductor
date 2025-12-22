# src/programs/neovim/options.nix
# Vim options and globals - LazyVim-quality modern defaults
#
# Design: Every option chosen for polyglot development excellence
{ pkgs }:

{
  globals = {
    # Leader keys
    mapleader = " ";
    maplocalleader = "\\";

    # Root detection (LSP > git > cwd)
    root_spec = [ "lsp" [ ".git" "lua" ] "cwd" ];

    # Auto-format on save (can be toggled with <leader>uf)
    autoformat = true;

    # Disable unused providers for performance
    loaded_python3_provider = 0;
    loaded_ruby_provider = 0;
    loaded_perl_provider = 0;
    loaded_node_provider = 0;
  };

  opts = {
    # =========================================================================
    # LINE NUMBERS
    # =========================================================================
    number = true;
    relativenumber = true;
    signcolumn = "yes"; # Always show, prevents layout shift

    # =========================================================================
    # INDENTATION (2 spaces, expandtab)
    # =========================================================================
    expandtab = true;
    shiftwidth = 2;
    tabstop = 2;
    softtabstop = 2;
    smartindent = true;
    shiftround = true; # Round indent to multiple of shiftwidth

    # =========================================================================
    # SEARCH
    # =========================================================================
    ignorecase = true;
    smartcase = true; # Case-sensitive if uppercase in pattern
    hlsearch = true;
    incsearch = true;
    inccommand = "nosplit"; # Live preview for substitutions

    # =========================================================================
    # UI - MODERN FEEL
    # =========================================================================
    termguicolors = true;
    cursorline = true;
    scrolloff = 8; # Keep 8 lines visible above/below cursor
    sidescrolloff = 8;
    wrap = false;
    linebreak = true; # Wrap at word boundaries when wrap is enabled
    showmode = false; # Lualine shows mode
    cmdheight = 1;
    laststatus = 3; # Global statusline
    pumheight = 10; # Popup menu height
    pumblend = 10; # Popup transparency
    winblend = 0; # Window transparency
    list = true; # Show invisible characters
    listchars = "tab:» ,trail:·,nbsp:␣";
    fillchars = "eob: ,fold:·,foldopen:▼,foldsep:│,foldclose:▶";
    smoothscroll = true; # Neovim 0.10+
    conceallevel = 2; # Hide markup in markdown

    # =========================================================================
    # SPLITS
    # =========================================================================
    splitbelow = true;
    splitright = true;
    splitkeep = "screen"; # Keep text on screen when splitting

    # =========================================================================
    # PERFORMANCE
    # =========================================================================
    updatetime = 200; # Faster CursorHold (default 4000)
    timeoutlen = 300; # Faster which-key popup
    redrawtime = 1500; # Time for syntax highlighting
    lazyredraw = false; # Don't redraw during macros (causes issues)

    # =========================================================================
    # FILES & UNDO
    # =========================================================================
    swapfile = false;
    backup = false;
    writebackup = false;
    undofile = true;
    undolevels = 10000;
    autowrite = true; # Auto-save before commands like :next

    # =========================================================================
    # CLIPBOARD
    # =========================================================================
    clipboard = "unnamedplus"; # Use system clipboard

    # =========================================================================
    # MOUSE
    # =========================================================================
    mouse = "a"; # Enable mouse in all modes
    mousemoveevent = true; # Enable mouse move events

    # =========================================================================
    # COMPLETION
    # =========================================================================
    completeopt = "menu,menuone,noselect";
    wildmode = "longest:full,full"; # Command-line completion

    # =========================================================================
    # FOLDING (Treesitter-based)
    # =========================================================================
    foldmethod = "expr";
    foldexpr = "v:lua.vim.treesitter.foldexpr()";
    foldtext = ""; # Use treesitter for fold text
    foldlevel = 99;
    foldlevelstart = 99;
    foldenable = true;

    # =========================================================================
    # SESSION
    # =========================================================================
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds";

    # =========================================================================
    # GREP (use ripgrep)
    # =========================================================================
    grepformat = "%f:%l:%c:%m";
    grepprg = "rg --vimgrep";

    # =========================================================================
    # DIFF
    # =========================================================================
    diffopt = "internal,filler,closeoff,hiddenoff,algorithm:histogram,linematch:60";

    # =========================================================================
    # SHELL
    # =========================================================================
    shell = "${pkgs.bash}/bin/bash";

    # =========================================================================
    # FORMATTING
    # =========================================================================
    formatexpr = "v:lua.require'conform'.formatexpr()";
    formatoptions = "jcroqlnt"; # Better format options

    # =========================================================================
    # SPELLING
    # =========================================================================
    spelllang = "en";
    spelloptions = "camel"; # Recognize CamelCase words

    # =========================================================================
    # VIRTUAL EDIT
    # =========================================================================
    virtualedit = "block"; # Allow cursor beyond end of line in visual block
  };
}
