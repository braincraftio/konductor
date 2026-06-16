# src/devshells/frontend.nix
# Frontend development shell for desktop applications (Tauri, Electron, etc.)
#
# Accumulative hierarchy: base → full → konductor → frontend
#
# Adds to konductor:
#   - Playwright browser dependencies for E2E testing
#   - Tauri 2.x build dependencies (GTK, WebKitGTK, OpenSSL, etc.) [Linux only]
#
# Use this shell for projects like SpiritStream (Tauri), not #full or #rust.

{ konductorShell
, pkgs
, packages
, versions
, programs
, config
, ...
}:

let
  inherit (packages) tauri;
in
konductorShell.overrideAttrs (old: {
  name = "frontend";

  nativeBuildInputs = old.nativeBuildInputs
    ++ [ pkgs.playwright-driver.browsers ]
    # Tauri 2.x desktop application build dependencies (Linux only)
    ++ tauri.packages;

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "frontend";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  } // tauri.env; # OPENSSL_NO_VENDOR, ZSTD_SYS_USE_PKG_CONFIG

  shellHook = ''
    # Tauri runtime libraries (GTK, WebKit, OpenSSL, compression)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath ([
      pkgs.openssl
    ] ++ tauri.buildInputs)}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Tauri shell setup (PATH ordering for Nix binaries)
    ${tauri.shellHook}
  '' + old.shellHook + ''
    echo "Frontend shell ready (Playwright + Tauri 2.x enabled)"

    # Clean up shellHook from env output (must be at very end)
    unset shellHook
  '';
})
