# src/overlays/flakehub-push.nix
# flakehub-push built from the commit the publish-flake action pins.
#
# The DeterminateSystems/flakehub-push action fetches its Rust binary at run
# time from install.determinate.systems (default: the moving `main` branch),
# independent of the action SHA. Building it here and passing it as
# `source-binary` puts the binary under the same version and hash management
# as every other release record.
#
# Upstream builds with current stable Rust; the rust-overlay toolchain pinned
# in versions.nix matches that (nixos-26.05 ships rustc 1.95.0).
#
# Version bump procedure:
#   Update flakehub-push.rev, hash, and cargoHash together in
#   src/lib/versions.nix, and the action SHA in
#   .github/actions/publish-flake/action.yml to the same rev.

let
  versions = import ../lib/versions.nix;
  flakehubPush = versions.flakehub-push;
in

_final: prev:
let
  rustToolchain = prev.rust-bin.stable.${versions.languages.rust.version}.minimal;
  rustPlatform = prev.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
{
  flakehub-push = rustPlatform.buildRustPackage {
    pname = "flakehub-push";
    version = "${flakehubPush.version}-unstable-${builtins.substring 0 7 flakehubPush.rev}";

    src = prev.fetchFromGitHub {
      owner = "DeterminateSystems";
      repo = "flakehub-push";
      inherit (flakehubPush) rev hash;
    };

    inherit (flakehubPush) cargoHash;

    meta = with prev.lib; {
      description = "Publish Nix flakes to FlakeHub";
      homepage = "https://github.com/DeterminateSystems/flakehub-push";
      license = licenses.asl20;
      mainProgram = "flakehub-push";
    };
  };
}
