# src/devshells/default.nix
# DevShell aggregation - exports all available development shells
#
# Package composition is defined in ../packages/ (single source of truth)
# All devshells import from src/packages/ for consistency
#
# Shells:
#   default   - Unopinionated foundation (no languages, no IDE)
#   python    - Python development
#   go        - Go development
#   node      - Node.js development
#   rust      - Rust development
#   dev       - Human workflow (IDE: neovim + tmux + forgejo-cli)
#   full      - Everything (all languages + dev)
#   konductor - Self-hosting (full + container/VM build tools) [Linux only]
#   ci        - CI/CD runner (all languages + forgejo + build tools) [Linux only]
#
# Platform Support:
#   All shells work on Linux and macOS except konductor and ci which require
#   Linux-specific virtualization packages (qemu_kvm, libvirt, OVMF, etc.)

{ pkgs, lib, versions, programs, ... }:

let
  # Platform detection
  isLinux = pkgs.stdenv.isLinux;

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions; };

  # Single source of truth for package composition
  # Config is passed to ensure all linters/formatters are wrapped
  packages = import ../packages { inherit pkgs lib versions config; };

  # Base shell configuration (shared by all devshells)
  baseShell = import ./base.nix { inherit pkgs lib versions packages; };

  # Helper to create a Linux-only shell with clear error message
  linuxOnly = name: shell:
    if isLinux then shell
    else throw ''
      The '${name}' devshell requires Linux.

      It includes Linux-specific virtualization packages:
        qemu_kvm, libvirt, virt-manager, libguestfs, OVMF

      On macOS, use one of these cross-platform shells instead:
        nix develop .#full      # All languages + IDE tools
        nix develop .#dev       # IDE tools only
        nix develop .#default   # Base tools only
    '';

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
  dev = import ./dev.nix { inherit baseShell pkgs packages programs config; };

  # Full: Everything - all languages + dev tools
  full = import ./full.nix { inherit baseShell pkgs packages versions programs config; };

  # Konductor: Self-hosting - full + container/VM build tools [Linux only]
  # Use inside QCOW2 VM to get docker, qemu, libvirt, etc.
  konductor = linuxOnly "konductor" (import ./konductor.nix { inherit baseShell pkgs packages versions programs config; });

  # CI: Forgejo Actions runner environment [Linux only]
  # All languages + forgejo runner/cli + container/VM build tools
  ci = linuxOnly "ci" (import ./ci.nix { inherit baseShell pkgs packages versions programs config; });
}
