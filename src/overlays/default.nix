# src/overlays/default.nix
# Overlay composition

{ nixpkgs-unstable, k0s-nix, ... }:

[
  # Version-pinned packages
  (import ./versions.nix)

  # k0s Kubernetes distribution binaries (pkgs.k0s, pkgs.k0s_1_27..k0s_1_35)
  # from the k0s-nix flake input. Version selection for konductor consumers:
  # src/lib/versions.nix kubernetes.k0s.attr. Linux-only packages; Darwin
  # surfaces never reference them (k0sctl is the cross-platform client).
  k0s-nix.overlays.default

  # k0sctl tip-of-spear pin (ahead of both nixpkgs channels)
  (import ./k0s.nix)

  # Vim plugin fixes (lualine sandbox test failures)
  (import ./vim-plugins.nix)

  # ttyd with embedded Nerd Fonts for web terminal
  (import ./ttyd.nix)

  # Pre-built code-server binary (avoids 2-4 hour source build)
  (import ./code-server.nix)

  # direnv CGO fix for Darwin — buildGoModule in nixpkgs 25.11 requires
  # env.CGO_ENABLED but direnv's GNUmakefile passes -linkmode=external on
  # Darwin which needs CGO. Without this, direnv fails to build on aarch64-darwin.
  (_final: prev: {
    direnv = prev.direnv.overrideAttrs (
      old:
      prev.lib.optionalAttrs prev.stdenv.isDarwin {
        env = (old.env or { }) // {
          CGO_ENABLED = "1";
        };
      }
    );
  })

  # Unstable packages overlay — apply direnv CGO fix here too since
  # mise and other unstable packages depend on unstable.direnv
  (
    _final: prev:
    let
      direnvCgoOverlay = uFinal: uPrev: {
        direnv = uPrev.direnv.overrideAttrs (
          old:
          uPrev.lib.optionalAttrs uPrev.stdenv.isDarwin {
            env = (old.env or { }) // {
              CGO_ENABLED = "1";
            };
          }
        );
      };
    in
    {
      unstable = import nixpkgs-unstable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
        overlays = [
          direnvCgoOverlay
        ];
      };
    }
  )
]
