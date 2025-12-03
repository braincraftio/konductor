# src/packages/languages.nix
# Version-locked language runtimes + package managers
# Individual exports for each language to support per-devshell composition

{ pkgs, versions }:

let
  langs = versions.languages;
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
    black
    isort
  ];

  # ===========================================================================
  # Go
  # ===========================================================================
  goPackages = with pkgs; [
    pkgs."go_${langs.go.version}"
    gopls
    delve
    golangci-lint
    gofumpt
    gotools
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
      extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
    })
    cargo-watch
    cargo-edit
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
