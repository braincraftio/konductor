# src/overlays/default.nix
# Overlay composition

{ nixpkgs-unstable, ... }:

[
  # Version-pinned packages
  (import ./versions.nix)

  # Vim plugin fixes (lualine sandbox test failures)
  (import ./vim-plugins.nix)

  # Unstable packages overlay
  (_final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (prev.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  })
]
