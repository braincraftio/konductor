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

  # atuin tip-of-spear pin — prevents SQLite migration skew between
  # devshell and home-manager consumers on different nixpkgs channels
  (import ./atuin.nix)

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
      prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
        env = (old.env or { }) // {
          CGO_ENABLED = "1";
        };
      }
    );
  })

  # ld64-957.1 SIGTRAP fix — ld64 crashes linking ObjC framework code
  # on macOS 26 (Darwin 25.x). Host .tbd stubs are incompatible with
  # ld64's TAPI parser. Force lld for all affected packages (same
  # pattern as glib/emacs/gtk3/codex in upstream nixpkgs master,
  # ref NixOS/nixpkgs#116700). The consumed nixpkgs fork
  # (usrbinkat/nixpkgs/gssproxy-package-and-module) is behind master
  # and does not yet include these fixes.
  (
    _final: prev:
    let
      # Rust packages: pass -fuse-ld=lld through the compiler driver via RUSTFLAGS
      useLldRust =
        pkg:
        pkg.overrideAttrs (
          old:
          prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
            RUSTFLAGS = (old.RUSTFLAGS or "") + " -C link-arg=-fuse-ld=lld";
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.llvmPackages.lld ];
          }
        );
      # C/C++/ObjC packages: pass -fuse-ld=lld via NIX_CFLAGS_LINK (compiler driver flag)
      # Also add -headerpad_max_install_names so nixpkgs fixupPhase can rewrite rpaths
      useLldCC =
        pkg:
        pkg.overrideAttrs (
          old:
          prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
            NIX_CFLAGS_LINK = (old.NIX_CFLAGS_LINK or "") + " -fuse-ld=lld -Wl,-headerpad_max_install_names";
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.llvmPackages.lld ];
          }
        );
    in
    {
      cargo-watch = useLldRust prev.cargo-watch;
      starship = useLldRust prev.starship;
      livekit-libwebrtc = useLldCC prev.livekit-libwebrtc;
    }
  )

  # Unstable packages overlay — apply direnv CGO fix here too since
  # mise and other unstable packages depend on unstable.direnv
  (
    _final: prev:
    let
      direnvCgoOverlay = uFinal: uPrev: {
        direnv = uPrev.direnv.overrideAttrs (
          old:
          uPrev.lib.optionalAttrs uPrev.stdenv.hostPlatform.isDarwin {
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
