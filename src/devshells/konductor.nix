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
# SSH config from: ../config/shell/ssh.nix
# OpenCode theme from: ../config/opencode/
# Atuin shell history from: ../config/shell/atuin.nix

{ baseShell
, pkgs
, packages
, versions
, programs
, config
, ...
}:

let
  langs = versions.languages;
  inherit (packages) konductor;
in

baseShell.overrideAttrs (old: {
  name = "konductor";

  # Everything from full + konductor self-hosting packages + CI tools
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs =
    old.nativeBuildInputs
    # IDE tools (neovim + tmux from programs, rest from packages.nix)
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ packages.idePackages
    # All languages from packages.nix
    ++ packages.pythonPackages
    ++ packages.goPackages
    ++ packages.nodejsPackages
    ++ packages.rustPackages
    # Atuin shell history (local-only by default, sync via ATUIN_SYNC=true)
    ++ config.shell.atuin.packages
    # Note: forgejo-cli and tea are in cli.nix (inherited via base shell)
    # forgejo-runner is NOT included here - it runs as a systemd service
    # and including it would cause service restarts during devshell rebuilds
    # Self-hosting: container + VM build tools
    ++ konductor.packages
    # ttyd web terminal with Catppuccin Frappé theme
    ++ programs.ttyd.packages
    # NOTE: C++ stdlib for Pulumi grpc no longer needed (native solution in packages/pulumi.nix)
    # Keeping for other potential native extension use cases
    ++ [ pkgs.stdenv.cc.cc.lib ];

  shellHook = ''
    # Runtime libraries (dynamic: appends to existing LD_LIBRARY_PATH)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.xz
      pkgs.zstd
    ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  ''
  + old.shellHook
  + ''
    # SSH identity detection (dynamic, needs $HOME)
    ${config.shell.ssh.shellHook}

    # OpenCode theme (empty hook)
    ${config.opencode.shellHook}

    # Atuin data dir creation (dynamic, needs $HOME)
    ${config.shell.atuin.shellHook}

    # Program hooks
    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

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

    # Konductor self-hosting
    ${konductor.shellHook}

    # Forgejo CI/CD (conditional)
    ${programs.forgejo.shellHook}

    # Update PATH (depends on dynamic vars above)
    # Python env MUST be first — mkShell puts bare python3 in PATH from
    # withPackages build deps; this ensures the -env wrapper wins.
    export PATH="${packages.pythonEnv}/bin:$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    if [ -z "''${KONDUCTOR_QUIET:-}" ]; then
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
      echo "  qemu, libvirt, virt-sparsify, OVMF"
      echo ""
      echo "Git Forge CLIs:"
      echo "  fj (forgejo-cli), tea (gitea-cli), gh (github-cli)"
      echo ""
      echo "Commands:  mise run help"
      echo ""
    fi

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env =
    old.env
    // {
      # Shell identity
      KONDUCTOR_SHELL = "konductor";
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
      # Docker
      DOCKER_BUILDKIT = "1";
    }
    // (konductor.env pkgs)
    // config.shell.ssh.env
    // config.opencode.env
    // config.shell.atuin.env
    // programs.tmux.env;
})
