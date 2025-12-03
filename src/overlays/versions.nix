# src/overlays/versions.nix
# Version-pinned package overlays

let
  versions = import ../lib/versions.nix;
  langs = versions.languages;
in

_final: prev: {
  # Konductor namespace for version-locked packages
  konductor = {
    # Python with pinned version
    python = prev."python${langs.python.version}".override {
      packageOverrides = _pythonSelf: _pythonSuper: {
        # Custom Python package overrides can go here
      };
    };

    # Go with pinned version
    go = prev."go_${langs.go.version}";

    # Node.js with pinned version
    nodejs = prev."nodejs_${langs.node.version}";

    # Rust with pinned version (from rust-overlay)
    rustc = prev.rust-bin.stable."${langs.rust.version}".default.override {
      extensions = [ "rust-src" "rust-analyzer" ];
    };
  };
}
