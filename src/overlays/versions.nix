# src/overlays/versions.nix
# Version-pinned package overlays
#
# The single place where src/lib/versions.nix versions become nixpkgs
# packages. Attribute names come from src/lib/version-attrs.nix; consumers
# select through pkgs.konductor.* and never build attribute names themselves:
# sync-versions:begin overlay-attrs
#   python "3.13" -> python313       go "1.27" -> go_1_27
#   node   "26"   -> nodejs_26       k0s "1.36" -> k0s_1_36
#   rust   "1.99.1" -> rust-bin.stable."1.99.1"
# sync-versions:end overlay-attrs

let
  versions = import ../lib/versions.nix;
  attrs = import ../lib/version-attrs.nix versions;
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
    python = prev.${attrs.python}.override {
      packageOverrides = _pythonSelf: _pythonSuper: {
        # Custom Python package overrides can go here
      };
    };

    # Package set of the pinned interpreter (linters, ansible, pulumi wheels)
    pythonPackages = prev.${attrs.pythonPackages};

    # Go with pinned version
    go = prev.${attrs.go};

    # Node.js with pinned version
    nodejs = prev.${attrs.nodejs};

    # Rust with pinned version (from rust-overlay)
    rustc = prev.rust-bin.stable.${attrs.rust}.default.override {
      extensions = [
        "rust-src"
        "rust-analyzer"
      ];
    };

    # k0s series from the k0s-nix overlay (Linux-only package set). Read from
    # `final`: this overlay is composed before k0s-nix's, so `prev` lacks k0s_*.
    k0s = final.${attrs.k0s};
  };
}
