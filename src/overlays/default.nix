# src/overlays/default.nix
# Overlay composition

{ nixpkgs-unstable, ... }:

[
  # Version-pinned packages
  (import ./versions.nix)

  # Unstable packages overlay
  (_final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (prev.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  })
]
