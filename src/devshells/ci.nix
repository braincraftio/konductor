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
# SSH config from: ../config/shell/ssh.nix

{ baseShell, pkgs, packages, versions, programs, config, ... }:

let
  langs = versions.languages;
  inherit (packages) konductor;
in

baseShell.overrideAttrs (old: {
  name = "ci";

  # Everything needed for CI/CD:
  # - Base packages (core, network, cli, linters, formatters)
  # - All language toolchains
  # - Forgejo runner and CLI
  # - Container and VM build tools (from konductor packages)
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs
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
    # Runtime libraries (dynamic: appends to existing LD_LIBRARY_PATH)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.xz pkgs.zstd ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '' + old.shellHook + ''
    # SSH identity detection (dynamic, needs $HOME)
    ${config.shell.ssh.shellHook}

    # Python: auto-activate venv if present (dynamic)
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi

    # Go workspace (dynamic, needs $HOME)
    GOPATH="''${GOPATH:-$HOME/go}"
    GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"

    # Node (dynamic, needs $HOME)
    PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"

    # Rust (dynamic, needs $HOME)
    CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"

    # Docker host (dynamic, uses default if not set)
    DOCKER_HOST="''${DOCKER_HOST:-unix:///var/run/docker.sock}"

    # Update PATH (depends on dynamic vars above)
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    # Forgejo shell hook (conditional)
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
    echo "  forgejo-runner, fj (forgejo-cli)"
    echo "  docker, docker-compose, buildkit, skopeo, crane"
    echo "  qemu, libvirt, virt-sparsify, OVMF"
    echo ""
    echo "Build Commands:"
    echo "  nix build .#qcow2         # Build QCOW2 image"
    echo "  nix build .#oci           # Build OCI container"
    echo "  nix flake check           # Run all checks"
    echo ""

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    # Shell identity
    KONDUCTOR_SHELL = "ci";
    KONDUCTOR_SKIP_BANNER = "1";
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
    # Docker
    DOCKER_BUILDKIT = "1";
  } // (konductor.env pkgs) // config.shell.ssh.env;
})
