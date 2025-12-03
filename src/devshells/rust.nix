# src/devshells/rust.nix
# Rust development shell
#
# Package composition defined in: ../packages/

{ baseShell, packages, versions, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "rust";

  # packages.rustPackages from ./packages.nix (single source of truth)
  buildInputs = old.buildInputs ++ packages.rustPackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="rust"
    export name="rust"

    # Cargo home
    export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"
    export PATH="$CARGO_HOME/bin:$PATH"

    echo "Rust ${langs.rust.display} ready"
  '';

  env = old.env // {
    RUST_BACKTRACE = "1";
  };
})
