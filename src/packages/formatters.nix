# src/packages/formatters.nix
# Formatting tools - composed from config wrappers

{ pkgs, config ? null }:

let
  hasConfig = config != null;
in

{
  packages =
    if hasConfig then [
      # Wrapped formatters
      config.formatters.shfmt.package
      config.formatters.prettier.package
      config.formatters.taplo.package
      config.formatters.biome.package

      # Formatters without wrappers
      pkgs.gofumpt
      pkgs.nixpkgs-fmt
      pkgs.stylua
      pkgs.black
      pkgs.isort
    ] else
    # ERROR: config must be provided for wrapped formatters
    # Unwrapped formatters violate hermetic configuration standards
      throw "formatters.nix requires config parameter - unwrapped formatters are not permitted";

  shellHook = "";
  env = { };
}
