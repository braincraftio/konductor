# src/devshells/frontend.nix
# Frontend development shell
# Extends 'full' with Playwright browser dependencies

{
  baseShell,
  pkgs,
  packages,
  versions,
  programs,
  config,
  ...
}:

let
  fullShell = import ./full.nix {
    inherit
      baseShell
      pkgs
      packages
      versions
      programs
      config
      ;
  };
in
fullShell.overrideAttrs (old: {
  name = "frontend";

  buildInputs = old.buildInputs ++ [
    pkgs.playwright-driver.browsers
  ];

  env = old.env // {
    KONDUCTOR_SHELL = "frontend";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  shellHook = old.shellHook + ''
    echo "Frontend shell ready (Playwright enabled)"
  '';
})
