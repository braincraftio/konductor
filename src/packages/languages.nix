# src/packages/languages.nix
# Version-locked language runtimes + package managers
# Individual exports for each language to support per-devshell composition
#
# NOTE: Linters and formatters (ruff, mypy, bandit, black, isort, golangci-lint,
# gofumpt, prettier, biome) are NOT included here. They are provided as wrapped
# hermetic versions via src/config/ → src/packages/linters.nix and formatters.nix,
# and aggregated into packages.default. This separation prevents buildEnv
# collisions when these package sets are consumed by home-manager, nixos, or
# nix-darwin modules (which use buildEnv, not mkShell PATH shadowing).

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
      ps.cryptography
    ]))
    poetry
    uv
    pipx
    # ruff, mypy, bandit → wrapped in src/config/linters/ (in packages.default)
    # black, isort → wrapped in src/packages/formatters.nix (in packages.default)
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

    # golangci-lint → wrapped in src/config/linters/ (in packages.default)
    # gofumpt → in src/packages/formatters.nix (in packages.default)

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
    bun
    nodePackages.pnpm
    nodePackages.yarn
    nodePackages.typescript-language-server
    # typescript → bundled by wrangler in ide.nix, standalone causes buildEnv collision
    # prettier → wrapped in src/config/formatters/ (in packages.default)
    # biome → wrapped in src/config/formatters/ (in packages.default)
  ];

  # ===========================================================================
  # Rust
  # ===========================================================================
  rustPackages = with pkgs; [
    # Use minimal profile to exclude rust-docs (saves ~700MB + tens of thousands of small files)
    (rust-bin.stable."${langs.rust.version}".minimal.override {
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
