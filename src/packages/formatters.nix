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
      pkgs.black
      pkgs.isort
    ] else with pkgs; [
      # Unwrapped formatters for containers
      shfmt
      nixpkgs-fmt
      gofumpt
      black
      isort
      nodePackages.prettier
    ];

  shellHook = "";
  env = { };
}
