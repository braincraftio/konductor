# src/devshells/full.nix
# Full polyglot shell - everything included
# All languages + IDE tools
#
# Package composition defined in: ../packages/

{ baseShell, packages, versions, programs, pkgs, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "full";

  # All packages from ./packages.nix (single source of truth)
  buildInputs = old.buildInputs
    # IDE tools (neovim + tmux from programs, rest from packages.nix)
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ packages.idePackages
    # All languages from packages.nix
    ++ packages.pythonPackages
    ++ packages.goPackages
    ++ packages.nodejsPackages
    ++ packages.rustPackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="full"
    export name="full"

    # Native library support for pip-installed packages (grpc, etc.)
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"

    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

    # Python
    export UV_SYSTEM_PYTHON="1"
    export PYTHONDONTWRITEBYTECODE="1"
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi

    # Go
    export GOPATH="''${GOPATH:-$HOME/go}"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"

    # Node
    export PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"

    # Rust
    export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"

    # Update PATH
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    echo "Full polyglot ready"
    echo "  Python ${langs.python.display} | Go ${langs.go.display}"
    echo "  Node.js ${langs.node.display} | Rust ${langs.rust.display}"
  '';

  env = old.env // {
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
})
