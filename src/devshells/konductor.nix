# src/devshells/konductor.nix
# Konductor self-hosting shell - full polyglot + build tooling
#
# This is the "meta" shell for developing Konductor itself.
# Includes everything from #full plus container/VM build tools.
#
# Use inside QCOW2 VM: nix develop konductor#konductor
# Tools are fetched from Nix cache on-demand, keeping the base image lean.
#
# Package composition defined in: ../packages/

{ baseShell, pkgs, packages, versions, programs, ... }:

let
  langs = versions.languages;
  konductor = packages.konductor;
in

baseShell.overrideAttrs (old: {
  name = "konductor";

  # Everything from full + konductor self-hosting packages
  buildInputs = old.buildInputs
    # IDE tools (neovim + tmux from programs, rest from packages.nix)
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ packages.idePackages
    # All languages from packages.nix
    ++ packages.pythonPackages
    ++ packages.goPackages
    ++ packages.nodejsPackages
    ++ packages.rustPackages
    # Self-hosting: container + VM build tools
    ++ konductor.packages;

  shellHook = ''
    # Skip base banner - we show our own
    export KONDUCTOR_SKIP_BANNER=1
  '' + old.shellHook + ''
    export KONDUCTOR_SHELL="konductor"
    export name="konductor"

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

    # Konductor self-hosting
    ${konductor.shellHook}

    # Update PATH
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Konductor Self-Hosting Shell                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Languages:"
    echo "  Python ${langs.python.display} | Go ${langs.go.display}"
    echo "  Node.js ${langs.node.display} | Rust ${langs.rust.display}"
    echo ""
    echo "Build Tools:"
    echo "  docker, docker-compose, buildkit, skopeo, crane"
    echo "  qemu, libvirt, virt-manager, cdrkit"
    echo ""
    echo "Commands:  mise run help"
    echo ""
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
  } // konductor.env;
})
