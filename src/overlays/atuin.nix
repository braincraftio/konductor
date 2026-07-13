# src/overlays/atuin.nix
# Atuin pinned ahead of nixos-26.05, independent of nixpkgs channel drift.
#
# nixos-26.05 ships atuin 18.10.0. Migration skew between konductor
# devshells and home-manager consumers on different nixpkgs channels
# caused SQLite migration conflicts (migration 20260224000100 applied
# by newer atuin, absent in older). This overlay asserts a single version
# across all surfaces — devshells, home-manager, NixOS, QCOW2.
#
# Pinned to 18.16.1 (nixpkgs-unstable's version) rather than 18.17.0
# because 18.17.0 requires rustc >= 1.96.1 which exceeds the nixpkgs
# rustc (1.91.1). Using prev.rustPlatform keeps the overlay self-contained
# with zero consumer overhead — no rust-overlay dependency required.
#
# The derivation mirrors nixpkgs-unstable pkgs/by-name/at/atuin/package.nix.
#
# Version bump procedure:
#   1. src/lib/versions.nix — atuin.version
#   2. this file — src hash + cargoHash for the new tag
#   3. verify new version builds with nixpkgs-bundled rustc (no rust-overlay)

let
  versions = import ../lib/versions.nix;
  inherit (versions) atuin;
in

_final: prev: {
  atuin = prev.rustPlatform.buildRustPackage {
    pname = "atuin";
    inherit (atuin) version;

    src = prev.fetchFromGitHub {
      owner = "atuinsh";
      repo = "atuin";
      tag = "v${atuin.version}";
      hash = "sha256-XrJFetPs7TsbX5Cxekj+h3hlmQLoOpB7U+c36NM/jeA=";
    };

    cargoHash = "sha256-eqxeE7+UxBTdaYjlonOz6pYQ3mar8lNUd/K0CSuzquc=";

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
