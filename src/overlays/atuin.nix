# src/overlays/atuin.nix
# Atuin pinned to tip-of-spear, independent of nixpkgs channel drift.
#
# nixos-26.05 ships atuin 18.15.2 — three releases behind upstream.
# Migration skew between konductor devshells (which may run a different
# nixpkgs) and home-manager consumers caused SQLite migration conflicts
# (migration 20260224000100 applied by newer atuin, absent in older).
# This overlay asserts the version so all surfaces — devshells, home-manager
# module, NixOS module, QCOW2 — ship the same atuin regardless of their
# nixpkgs channel.
#
# The derivation mirrors upstream nixpkgs pkgs/by-name/at/atuin/package.nix.
#
# Version bump procedure:
#   1. src/lib/versions.nix — atuin.version
#   2. this file — src hash + cargoHash for the new tag

let
  versions = import ../lib/versions.nix;
  inherit (versions) atuin;
in

_final: prev:
let
  # atuin 18.17.0 requires rustc >= 1.96.1; nixos-26.05 ships 1.95.0.
  # Use rust-overlay (applied before this overlay) to get a sufficient toolchain.
  rustToolchain = prev.rust-bin.stable."1.96.1".default;
  rustPlatform = prev.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
{
  atuin = rustPlatform.buildRustPackage {
    pname = "atuin";
    inherit (atuin) version;

    src = prev.fetchFromGitHub {
      owner = "atuinsh";
      repo = "atuin";
      tag = "v${atuin.version}";
      hash = "sha256-cciogPSlbfiC9U3Dv+IGyuRI9PU9X4LdlequCFiG/a0=";
    };

    cargoHash = "sha256-QX1JupLZafRdMUZjl58iFjiPgLSTYZazRVyU88n5QP8=";

    # atuin's default features include 'check-updates', which do not make sense
    # for distribution builds. List all other default features.
    buildNoDefaultFeatures = true;
    buildFeatures = [
      "ai"
      "client"
      "clipboard"
      "daemon"
      "hex"
      "sync"
    ];

    nativeBuildInputs = [ prev.installShellFiles ];

    postInstall = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
      installShellCompletion --cmd atuin \
        --bash <($out/bin/atuin gen-completions -s bash) \
        --fish <($out/bin/atuin gen-completions -s fish) \
        --zsh <($out/bin/atuin gen-completions -s zsh)
    '';

    checkFlags = [
      "--skip=registration"
      "--skip=sync"
      "--skip=change_password"
      "--skip=multi_user_test"
    ];

    preCheck = ''
      export HOME=$(mktemp -d)
    '';

    meta = with prev.lib; {
      description = "Replacement for a shell history which records additional commands context with optional encrypted synchronization between machines";
      homepage = "https://github.com/atuinsh/atuin";
      changelog = "https://github.com/atuinsh/atuin/releases/tag/v${atuin.version}";
      license = licenses.mit;
      mainProgram = "atuin";
    };
  };
}
