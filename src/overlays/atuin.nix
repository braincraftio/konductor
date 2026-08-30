# src/overlays/atuin.nix
# Atuin pinned ahead of nixos-26.05, independent of nixpkgs channel drift.
#
# nixos-26.05 ships atuin 18.15.2. Migration skew between konductor
# devshells and home-manager consumers on different nixpkgs channels
# caused SQLite migration conflicts. This overlay asserts a single
# version across all surfaces — devshells, home-manager, NixOS, QCOW2.
#
# atuin >= 18.17.0 requires rustc >= 1.96.1; nixos-26.05 ships 1.95.0.
# Build uses rust-overlay toolchain pinned in versions.nix.
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
  # nixos-26.05 ships rustc 1.95.0; atuin >= 18.17.0 requires rustc >= 1.96.1.
  # Build with the rust-overlay toolchain pinned in versions.nix.
  rustToolchain = prev.rust-bin.stable.${versions.languages.rust.version}.minimal;
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
      hash = "sha256-FjfG2w4HnYNdT7cztVzSGtcgj/9fLupgSu8bzV+uLtE=";
    };

    cargoHash = "sha256-HXRFjemrIVuBYpM3ISMtvnNEWFMfmfkhavNFgk5VbI4=";

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

    nativeBuildInputs = [
      prev.installShellFiles
      prev.pkg-config
    ];

    buildInputs = [
      prev.openssl
    ];

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
