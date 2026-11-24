# src/lib/version-attrs.nix
# nixpkgs attribute names derived from src/lib/versions.nix. Pure data, no pkgs:
# src/overlays/versions.nix selects packages by these names, and
# src/apps/sync-versions renders them into documentation.

versions:

let
  langs = versions.languages;
  dotsTo = sep: builtins.replaceStrings [ "." ] [ sep ];
in
{
  python = "python${dotsTo "" langs.python.version}";
  pythonPackages = "python${dotsTo "" langs.python.version}Packages";
  go = "go_${dotsTo "_" langs.go.version}";
  nodejs = "nodejs_${langs.node.version}";
  # Attribute path under rust-overlay's rust-bin.stable.
  rust = langs.rust.version;
  k0s = "k0s_${dotsTo "_" versions.kubernetes.k0s.version}";
}
