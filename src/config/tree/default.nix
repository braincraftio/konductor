# src/config/tree/default.nix
# Konductor `tree`: a Rust renderer (this directory's crate, a member of the
# Cargo workspace at the repository root) with tree-compatible options and
# drawing characters over ripgrep's ignore rules, per-file line counts, git status,
# .tree.toml configuration, and a footer accounting for every entry not
# listed. Both shell specifications run as install checks,
# so a build that does not meet it does not install.
#
# eza and git are baked in by store path: `tree --raw` runs eza --tree, and
# git status comes from the git CLI.

{
  pkgs,
  lib,
  rustToolchain,
}:

let
  root = ../../..;
  manifest = lib.importTOML ./Cargo.toml;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      ./Cargo.toml
      ./clippy.toml
      ./rustfmt.toml
      ./src
      ./tests
    ];
  };

  package = rustPlatform.buildRustPackage {
    pname = manifest.package.name;
    inherit (manifest.package) version;
    inherit src;
    cargoLock.lockFile = root + "/Cargo.lock";
    cargoBuildFlags = [
      "-p"
      manifest.package.name
    ];
    cargoTestFlags = [
      "-p"
      manifest.package.name
    ];

    env = {
      KONDUCTOR_TREE_EZA = lib.getExe pkgs.eza;
      KONDUCTOR_TREE_GIT = lib.getExe pkgs.git;
    };

    doInstallCheck = true;
    nativeInstallCheckInputs = [
      pkgs.git
      pkgs.ripgrep
      pkgs.jq
      pkgs.python3
    ];
    installCheckPhase = ''
      runHook preInstallCheck
      bash src/config/tree/tests/spec.sh "$out/bin/tree"
      bash src/config/tree/tests/consumers.sh "$out/bin/tree"
      runHook postInstallCheck
    '';

    meta = {
      inherit (manifest.package) description;
      license = lib.licenses.mit;
      mainProgram = "tree";
    };
  };
in
{
  inherit package;

  # eza for direct access (`tree --raw` runs it).
  unwrapped = pkgs.eza;

  meta = {
    inherit (package.meta) description;
    configurable = true;
    defaults = {
      depth = "unlimited";
      budget = 12000;
      colorize = "auto";
      ignoreRules = "ripgrep";
      configFile = ".tree.toml";
    };
  };
}
