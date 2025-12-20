# src/devshells/ci.nix
# CI/CD devshell for Forgejo Actions runners
#
# This shell is optimized for running Forgejo Actions workflows
# that build and test the Konductor flake, containers, and QCOW2 images.
#
# Includes:
#   - All languages (Python, Go, Node.js, Rust)
#   - All config-wrapped linters/formatters
#   - Container build tools (docker, buildkit, skopeo)
#   - VM build tools (qemu, libvirt)
#   - Forgejo runner and CLI
#   - Nix tools (cachix)
#
# Usage in Konductor VM:
#   nix develop github:containercraft/konductor#ci
#
# Package composition defined in: ../packages/

{ baseShell, pkgs, packages, versions, programs, ... }:

let
  langs = versions.languages;
  konductor = packages.konductor;
in

baseShell.overrideAttrs (old: {
  name = "ci";

  # Everything needed for CI/CD:
  # - Base packages (core, network, cli, linters, formatters)
  # - All language toolchains
  # - Forgejo runner and CLI
  # - Container and VM build tools (from konductor packages)
  buildInputs = old.buildInputs
    # All languages from packages.nix
    ++ packages.pythonPackages
    ++ packages.goPackages
    ++ packages.nodejsPackages
    ++ packages.rustPackages
    # Forgejo runner + CLI
    ++ programs.forgejo.runnerPackages
    ++ programs.forgejo.cliPackages
    # Self-hosting: container + VM build tools
    ++ konductor.packages;

  shellHook = ''
    # Skip base banner - we show our own
    export KONDUCTOR_SKIP_BANNER=1
  '' + old.shellHook + ''
    export KONDUCTOR_SHELL="ci"
    export name="ci"
    export CI="true"

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

    # Docker
    export DOCKER_HOST="''${DOCKER_HOST:-unix:///var/run/docker.sock}"
    export DOCKER_BUILDKIT=1

    # Update PATH
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    # Forgejo shell hook
    ${programs.forgejo.shellHook}

    # Konductor self-hosting shell hook
    ${konductor.shellHook}

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 Konductor CI/CD Shell                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Languages:"
    echo "  Python ${langs.python.display} | Go ${langs.go.display}"
    echo "  Node.js ${langs.node.display} | Rust ${langs.rust.display}"
    echo ""
    echo "CI Tools:"
    echo "  forgejo-runner, forgejo-cli"
    echo "  docker, docker-compose, buildkit, skopeo, crane"
    echo "  qemu, libvirt, cdrkit"
    echo ""
    echo "Build Commands:"
    echo "  nix build .#qcow2         # Build QCOW2 image"
    echo "  nix build .#oci           # Build OCI container"
    echo "  nix flake check           # Run all checks"
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
    # CI
    CI = "true";
  } // konductor.env;
})
