# src/devshells/base.nix
# Base development shell - unopinionated foundation
#
# This is the default shell for all targets (flake, OCI, QCOW2)
# NO languages, NO IDE - just the essentials for any workflow
#
# Package composition defined in: ../packages/

{ pkgs, versions, packages, ... }:

pkgs.mkShell {
  name = "default";

  # packages.default from ./packages.nix (single source of truth)
  buildInputs = packages.default;

  shellHook = ''
    export KONDUCTOR_SHELL="default"
    export name="default"

    # XDG Base Directory
    export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"

    # Welcome message
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Konductor DevShell                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Available shells:"
    echo "  nix develop              Default (current)"
    echo "  nix develop .#python     Python ${versions.languages.python.display}"
    echo "  nix develop .#go         Go ${versions.languages.go.display}"
    echo "  nix develop .#node       Node.js ${versions.languages.node.display}"
    echo "  nix develop .#rust       Rust ${versions.languages.rust.display}"
    echo "  nix develop .#dev        IDE (neovim + tmux)"
    echo "  nix develop .#full       Everything"
    echo ""
    echo "Commands:  mise run help"
    echo ""
  '';

  # Use centralized environment variables
  env = import ../lib/env.nix;
}
