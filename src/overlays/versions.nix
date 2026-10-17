# src/overlays/versions.nix
# Version-pinned package overlays
#
# The single place where src/lib/versions.nix versions become nixpkgs
# attributes. Consumers select through pkgs.konductor.* and never build
# attribute names themselves:
#   python "3.13" -> python313       go "1.27" -> go_1_27
#   node   "26"   -> nodejs_26       k0s "1.36" -> k0s_1_36
#   rust   "1.99.1" -> rust-bin.stable."1.99.1"

let
  versions = import ../lib/versions.nix;
  langs = versions.languages;
  dotsTo = sep: builtins.replaceStrings [ "." ] [ sep ];
in

final: prev: {
  # pipx test suite has formatting assertion failures on nixos-26.05
  # (PEP 440 spacing change: "pkg@ url" vs "pkg @ url"). Disable tests.
  pipx = prev.pipx.overridePythonAttrs (_old: {
    doCheck = false;
  });

  # Konductor namespace for version-locked packages
  konductor = {
    # Python with pinned version
    python = prev."python${dotsTo "" langs.python.version}".override {
      packageOverrides = _pythonSelf: _pythonSuper: {
        # Custom Python package overrides can go here
      };
    };

    # Package set of the pinned interpreter (linters, ansible, pulumi wheels)
    pythonPackages = prev."python${dotsTo "" langs.python.version}Packages";

    # Go with pinned version
    go = prev."go_${dotsTo "_" langs.go.version}";

    # Node.js with pinned version
    nodejs = prev."nodejs_${langs.node.version}";

    # Rust with pinned version (from rust-overlay)
    rustc = prev.rust-bin.stable."${langs.rust.version}".default.override {
      extensions = [
        "rust-src"
        "rust-analyzer"
      ];
    };

    # k0s series from the k0s-nix overlay (Linux-only package set). Read from
    # `final`: this overlay is composed before k0s-nix's, so `prev` lacks k0s_*.
    k0s = final."k0s_${dotsTo "_" versions.kubernetes.k0s.version}";
  };
}
