# src/devshells/frontend.nix
# Frontend development shell for desktop applications (Tauri, Electron, etc.)
#
# Extends 'konductor' with:
#   - Playwright browser dependencies for E2E testing
#   - Tauri 2.x build dependencies (GTK, WebKitGTK, OpenSSL, etc.) [Linux only]
#
# This is the appropriate shell for building desktop GUI applications.
# Use this shell for projects like SpiritStream (Tauri), not #full or #rust.

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
  inherit (packages) tauri;
in
konductorShell.overrideAttrs (old: {
  name = "frontend";

  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs
    ++ [ pkgs.playwright-driver.browsers ]
    # Tauri 2.x desktop application build dependencies (Linux only)
    ++ tauri.packages;

  env = old.env // {
    KONDUCTOR_SHELL = "frontend";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  } // tauri.env;  # OPENSSL_NO_VENDOR, ZSTD_SYS_USE_PKG_CONFIG

  shellHook = ''
    # Tauri runtime libraries (GTK, WebKit, OpenSSL, compression)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath ([
      pkgs.openssl
    ] ++ tauri.buildInputs)}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Tauri shell setup (PATH ordering for Nix binaries)
    ${tauri.shellHook}
  '' + old.shellHook + ''
    echo "Frontend shell ready (Playwright + Tauri 2.x enabled)"
  '';
})
