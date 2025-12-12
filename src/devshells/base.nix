# src/devshells/base.nix
# Base development shell - unopinionated foundation
#
# This is the default shell for all targets (flake, OCI, QCOW2)
# NO languages, NO IDE - just the essentials for any workflow
#
# Package composition defined in: ../packages/

{ pkgs, versions, packages, ... }:

let
  # Read native bashrc for aliases and shell setup
  bashrcContent = builtins.readFile ../config/shell/.bashrc;
in

pkgs.mkShell {
  name = "default";

  # packages.default from ./packages.nix (single source of truth)
  buildInputs = packages.default;

  shellHook = ''
    export KONDUCTOR_SHELL="default"
    export name="default"

    # Source hermetic bashrc (aliases, shell options, prompt)
    ${bashrcContent}

    # Welcome message (skipped if KONDUCTOR_SKIP_BANNER is set by derived shells)
    if [ -z "$KONDUCTOR_SKIP_BANNER" ]; then
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
      echo "  nix develop .#konductor  Self-hosting (full + docker/qemu/libvirt)"
      echo ""
      echo "Commands:  mise run help"
      echo ""
    fi
  '';

  # Use centralized environment variables
  env = import ../lib/env.nix;
}
