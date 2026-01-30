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
  # Using `packages` (modern) instead of `buildInputs` (legacy)
  # This properly sets up PATH and XDG_DATA_DIRS for CLI tools
  packages = packages.default;

  shellHook = ''
    # =========================================================================
    # IDE Agent Terminal Guard (MUST BE FIRST)
    # =========================================================================
    # Skip all shellHook setup for Windsurf/Cursor/VS Code agent terminals.
    # These agents spawn terminals to run commands but the interactive hooks
    # prevent clean shell exit, causing agent hangs waiting for OSC 633 sequences.
    # Tracing: check /tmp/devshell-hook.trace after commands
    _trace_hook() { echo "[$(date '+%H:%M:%S.%3N')] [shellHook] $*" >> /tmp/devshell-hook.trace; }
    _trace_hook "=== shellHook starting: WINDSURF_CASCADE_TERMINAL=''${WINDSURF_CASCADE_TERMINAL:-<unset>} ==="
    if [[ -n "''${WINDSURF_CASCADE_TERMINAL:-}" ]]; then
      _trace_hook "GUARD TRIGGERED: Skipping shellHook, returning early"
      return 0 2>/dev/null || true
    fi
    _trace_hook "GUARD PASSED: Running full shellHook"

    # KONDUCTOR_SHELL and name set via env attribute

    # Source bash-completion for programmable completions
    # This enables lazy-loading of completions from XDG_DATA_DIRS
    if [ -f "${pkgs.bash-completion}/share/bash-completion/bash_completion" ]; then
      source "${pkgs.bash-completion}/share/bash-completion/bash_completion"
    fi

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

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Use centralized environment variables + shell identity + package env
  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  # SHELL must point to bashInteractive (not bash) for dirspell, complete, etc.
  env = import ../lib/env.nix // packages.env // {
    KONDUCTOR_SHELL = "default";
    SHELL = "${pkgs.bashInteractive}/bin/bash";
  };
}
