# src/devshells/frontend.nix
# Frontend development shell
# Extends 'konductor' with Playwright browser dependencies
# Includes all VM/container build tools (OVMF, qemu, libvirt) for QCOW2 builds

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
  konductorShell = import ./konductor.nix {
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
konductorShell.overrideAttrs (old: {
  name = "frontend";

  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs ++ [
    pkgs.playwright-driver.browsers
  ];

  env = old.env // {
    KONDUCTOR_SHELL = "frontend";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  shellHook = old.shellHook + ''
    echo "Frontend shell ready (Playwright + VM build tools enabled)"
  '';
})
