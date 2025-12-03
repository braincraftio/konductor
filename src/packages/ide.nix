# src/packages/ide.nix
# IDE and developer experience tools

{ pkgs }:

let
  # Lua 5.1 with required packages for neovim plugins
  luaEnv = pkgs.lua5_1.withPackages (ps: with ps; [
    luarocks
    # Required by rest.nvim
    lua-curl
    mimetypes
    xml2lua
  ]);
in
{
  packages = with pkgs; [
    lazygit # Git TUI
    htop # Process monitor
    bottom # System monitor (btm)
    bat # cat with syntax highlighting
    eza # Modern ls
    dust # Disk usage analyzer
    tree # Directory tree

    # Neovim dependencies (required for plugins)
    tree-sitter # Parser generator for nvim-treesitter (:TSInstallFromGrammar)
    luaEnv # Lua 5.1 with luarocks and rest.nvim dependencies

    # Snacks.nvim image support dependencies
    imagemagick # Image conversion (magick/convert)
    ghostscript # PDF rendering (gs)
    tectonic # LaTeX rendering for math expressions
    mermaid-cli # Mermaid diagram rendering (mmdc)

    # Render-markdown latex support
    python312Packages.pylatexenc # utftex for latex-to-unicode conversion
  ];

  shellHook = "";
  env = { };
}
