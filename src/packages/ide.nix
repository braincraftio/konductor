# src/packages/ide.nix
# IDE and developer experience tools
#
# Includes:
#   - TUI tools (lazygit, htop, btop, etc.)
#   - AI coding agents (opencode)
#   - Neovim plugin dependencies
#   - Cloudflare developer platform CLI tools
#   - LSP servers for Claude Code CLI code intelligence

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
    btop
    bottom # System monitor (btm)
    bat # cat with syntax highlighting
    eza # Modern ls
    dust # Disk usage analyzer
    tree # Directory tree

    # AI coding agents (from unstable - fast-moving packages)
    # opencode: 1.0.184 (unstable) vs 1.0.105 (25.11)
    unstable.opencode

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

    # Cloudflare developer platform CLI tools
    wrangler # CLI for Cloudflare Workers, Pages, KV, R2, D1, Workflows
    cloudflared # Cloudflare Tunnel, Access, DNS over HTTPS
    flarectl # CLI for interacting with Cloudflare account

    # Documentation site generation
    hugo # Static site generator for docs (Go-based, works with Docsy theme)

    # Language Server Protocol (LSP) servers for Claude Code CLI code intelligence
    # https://docs.anthropic.com/en/docs/claude-code/settings#code-intelligence
    gopls # Go LSP server
    lua-language-server # Lua LSP server
    pyright # Python LSP server
    rust-analyzer # Rust LSP server
    typescript-language-server # TypeScript/JavaScript LSP server
    nil # Nix LSP server

    # Git forge CLI tools (used as git credential helpers)
    gh # GitHub CLI (also used as git credential helper for GitHub)
    tea # Gitea/Forgejo CLI client (also used as git credential helper)
    # Note: forgejo-cli is provided by programs.forgejo.cliPackages

    # Model Context Protocol (MCP) servers for Claude Code
    github-mcp-server # GitHub issues, PRs, code search
    gitea-mcp-server # Forgejo/Gitea integration
    mcp-k8s-go # Kubernetes cluster interaction

    # Nix flake development tools
    flake-checker # Health checks for Nix flakes
    nvd # Nix package version diff tool
    nixfmt # Official Nix code formatter
  ];

  shellHook = "";
  env = { };
}
