# src/devshells/rust.nix
# Rust development shell
#
# Package composition defined in: ../packages/

{ baseShell, pkgs, packages, versions, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "rust";

  # packages.rustPackages from ./packages.nix (single source of truth)
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs ++ packages.rustPackages;

  shellHook = old.shellHook + ''
    # Runtime libraries for Rust crates using compression (cargo install targets)
    # Dynamic: appends to existing LD_LIBRARY_PATH
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.xz pkgs.zstd ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Cargo home (dynamic, needs $HOME)
    CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"
    export PATH="$CARGO_HOME/bin:$PATH"

    echo "Rust ${langs.rust.display} ready"

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "rust";
    RUST_BACKTRACE = "1";
  };
})
