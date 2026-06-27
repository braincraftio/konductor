# src/overlays/default.nix
# Overlay composition

{ nixpkgs-unstable, ... }:

[
  # Version-pinned packages
  (import ./versions.nix)

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
    direnv = prev.direnv.overrideAttrs (old: prev.lib.optionalAttrs prev.stdenv.isDarwin {
      env = (old.env or { }) // { CGO_ENABLED = "1"; };
    });
  })

  # Unstable packages overlay — apply direnv CGO fix here too since
  # mise and other unstable packages depend on unstable.direnv
  (_final: prev: let
    direnvCgoOverlay = uFinal: uPrev: {
      direnv = uPrev.direnv.overrideAttrs (old: uPrev.lib.optionalAttrs uPrev.stdenv.isDarwin {
        env = (old.env or { }) // { CGO_ENABLED = "1"; };
      });
    };
  in {
    unstable = import nixpkgs-unstable {
      inherit (prev.stdenv.hostPlatform) system;
      config.allowUnfree = true;
      overlays = [
        direnvCgoOverlay
        # Fix stale VSIX hash for anthropic.claude-code — marketplace payload changed,
        # nixpkgs-unstable hasn't merged the updated hash yet.
        # TODO: remove once nixpkgs-unstable ships with the correct hash
        (_: uPrev: {
          vscode-extensions = uPrev.vscode-extensions // {
            anthropic = (uPrev.vscode-extensions.anthropic or {}) // {
              claude-code = uPrev.vscode-extensions.anthropic.claude-code.overrideAttrs (old: {
                src = uPrev.fetchurl {
                  inherit (old.src) url name;
                  sha256 = "sha256-tCasNLg/Tu3uP69Mve9Kcqam1+JQkA/XyCMPy6aNPJM=";
                };
              });
            };
          };
        })
      ];
    };
  })
]
