# src/config/formatters/nixfmt.nix
# The single Nix formatter for this repository: nixfmt (RFC 166 style, the
# formatter nixpkgs itself enforces). Whole-tree formatting goes through
# src/config/formatters/treefmt.nix, which runs this binary with --verify.

{ pkgs }:

{
  package = pkgs.nixfmt;

  unwrapped = pkgs.nixfmt;
  configFile = null; # nixfmt has no config file; RFC 166 defaults (width 100)

  meta = {
    description = "Nix formatter (nixfmt, RFC 166 style)";
    configurable = false;
  };
}
