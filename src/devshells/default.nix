# src/devshells/default.nix
# DevShell aggregation - exports all available development shells
#
# Package composition is defined in ../packages/ (single source of truth)
# All devshells import from src/packages/ for consistency
#
# Shells:
#   default  - Unopinionated foundation (no languages, no IDE)
#   python   - Python development
#   go       - Go development
#   node     - Node.js development
#   rust     - Rust development
#   dev      - Human workflow (IDE: neovim + tmux)
#   full     - Everything (all languages + dev)

{ pkgs, lib, versions, programs, ... }:

let
  # Single source of truth for package composition
  packages = import ../packages { inherit pkgs lib versions; };

  # Base shell configuration (shared by all devshells)
  baseShell = import ./base.nix { inherit pkgs lib versions packages; };

in
{
  # Default: Unopinionated foundation
  # NO languages, NO IDE - just the essentials
  default = baseShell;

  # Language-specific shells (add their language to default)
  python = import ./python.nix { inherit baseShell pkgs packages versions; };
  go = import ./go.nix { inherit baseShell pkgs packages versions; };
  node = import ./node.nix { inherit baseShell pkgs packages versions; };
  rust = import ./rust.nix { inherit baseShell pkgs packages versions; };

  # Dev: Human workflow with IDE tools
  dev = import ./dev.nix { inherit baseShell pkgs packages programs; };

  # Full: Everything - all languages + dev tools
  full = import ./full.nix { inherit baseShell pkgs packages versions programs; };
}
