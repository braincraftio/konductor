# src/packages/languages.nix
# Version-locked language runtimes + package managers
# Individual exports for each language to support per-devshell composition

{ pkgs, lib, versions }:

let
  langs = versions.languages;
  inherit (pkgs) stdenv;
in

rec {
  # ===========================================================================
  # Python
  # ===========================================================================
  pythonPackages = with pkgs; [
    (pkgs."python${langs.python.version}".withPackages (ps: [
      ps.pip
      ps.ipython
      ps.pytest
    ]))
    poetry
    uv
    pipx
    ruff
    mypy
    bandit
  ] ++ lib.optionals (!stdenv.isDarwin) [
    # Darwin 25.x: black/isort pull setproctitle which fails tests in nix sandbox
    black
    isort
  ];

  # ===========================================================================
  # Go
  # ===========================================================================
  goPackages = with pkgs; [
    # Runtime
    pkgs."go_${langs.go.version}"

    # LSP and debugging
    gopls
    delve

    # Linting (wrapped in src/config/linters/golangci-lint/)
    golangci-lint

    # Formatting
    gofumpt

    # Go tools (stringer, guru, etc.)
    gotools

    # Release automation
    goreleaser # Build, release, and publish Go binaries
    git-cliff # Changelog generation from conventional commits

    # Code generation
    ogen # OpenAPI v3 server/client code generator
    cobra-cli # CLI scaffolding for Cobra applications
    go-swag # Swagger 2.0 RESTful API documentation generator
    mockgen # Mock generation for Go interfaces (uber/mock)
  ];

  # ===========================================================================
  # Node.js
  # ===========================================================================
  nodejsPackages = with pkgs; [
    pkgs."nodejs_${langs.node.version}"
    nodePackages.pnpm
    nodePackages.yarn
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
    biome
  ];

  # ===========================================================================
  # Rust
  # ===========================================================================
  rustPackages = with pkgs; [
    (rust-bin.stable."${langs.rust.version}".default.override {
      extensions = [
        "rust-src"
        "rust-analyzer"
        "clippy"
        "rustfmt"
      ];
    })
    cargo-watch
    cargo-edit
    cargo-tauri # Tauri CLI from nixpkgs (properly patched, no cargo install needed)
  ];

  # Runtime libraries for Rust crates that use compression
  # These are needed when users run `cargo install` for crates not in nixpkgs
  rustRuntimeLibs = with pkgs; [
    xz # provides liblzma.so.5
    zstd # provides libzstd.so
  ];

  # ===========================================================================
  # Combined packages
  # ===========================================================================
  packages = pythonPackages ++ goPackages ++ nodejsPackages ++ rustPackages;

  shellHook = "";

  env = {
    # Python
    UV_SYSTEM_PYTHON = "1";
    PYTHONDONTWRITEBYTECODE = "1";

    # Go
    GO111MODULE = "on";
    CGO_ENABLED = "1";

    # Node
    NODE_ENV = "development";

    # Rust
    RUST_BACKTRACE = "1";
  };
}
