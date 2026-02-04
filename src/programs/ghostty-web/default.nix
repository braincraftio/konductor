# src/programs/ghostty-web/default.nix
# Ghostty Web Terminal - PTY server package for Konductor
#
# Provides browser-accessible terminal via HTTP + WebSocket.
# Designed for KubeVirt VM deployment behind Envoy Gateway (OIDC).
#
# ESM Module Resolution:
# - Node.js ESM ignores NODE_PATH environment variable
# - Solution: Place server.js and node_modules as siblings
# - Use makeWrapper --chdir to set CWD to application directory
#
# Dependencies:
# - node-pty (microsoft/node-pty v1.1.0) - PTY management, built from source
# - ws - WebSocket server
# - ghostty-web - WASM terminal frontend (fetched from npm)

{ pkgs, lib, ... }:

let
  # ===========================================================================
  # GHOSTTY-WEB NPM PACKAGE (Frontend Assets)
  # ===========================================================================
  # Fetch pre-built distribution from npm (includes WASM binary)
  # Building from source requires Zig toolchain - avoid by using pre-built

  ghosttyWebPkg = pkgs.fetchzip {
    url = "https://registry.npmjs.org/ghostty-web/-/ghostty-web-0.4.0.tgz";
    hash = "sha256-ylBlhpFJaChMnNaSc+R/yvTLiDnjTH9Sz/HBr8CNU3k=";
    stripRoot = true;
  };

  # ===========================================================================
  # SERVER APPLICATION
  # ===========================================================================
  # Single derivation containing server.js + node_modules as siblings
  # This structure is REQUIRED for ESM module resolution
  #
  # Output structure:
  #   $out/bin/ghostty-web-server     (wrapper script)
  #   $out/lib/ghostty-web/
  #     ├── server.js                 (application entry)
  #     ├── index.html                (frontend template)
  #     ├── node_modules/             (dependencies - sibling to server.js)
  #     └── static/
  #         ├── ghostty-web.js        (WASM loader)
  #         └── ghostty-vt.wasm       (terminal core)

  ghosttyWebServer = pkgs.buildNpmPackage {
    pname = "ghostty-web-server";
    version = "1.0.0";

    src = ./.;

    # Hash for npm dependencies (node-pty + ws)
    # Regenerate with: nix-build -E 'let pkgs = import <nixpkgs> {}; in (import ./src/programs/ghostty-web { inherit pkgs; inherit (pkgs) lib; }).server'
    npmDepsHash = "sha256-hF4d0Gm+JklEOB6t/zMtTZHSl7Tnk2WehhE0iUFOQHw=";

    # Native module build requirements for node-pty
    nativeBuildInputs = with pkgs; [
      python3      # Required for node-gyp
      pkg-config
      makeWrapper
    ];

    # node-pty uses forkpty() on Linux which links against -lutil
    # This is provided by glibc, no explicit buildInput needed

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Create application directory structure
      mkdir -p $out/lib/ghostty-web/static
      mkdir -p $out/bin

      # Copy application code
      cp ${./server.js} $out/lib/ghostty-web/server.js

      # Copy node_modules (MUST be sibling of server.js for ESM resolution)
      cp -r node_modules $out/lib/ghostty-web/

      # Copy ALL static assets to single directory (frontend served via HTTP)
      # - index.html, ghostty-web.js, ghostty-vt.wasm all as siblings
      # - Relative imports in index.html (./ghostty-web.js) resolve correctly
      cp ${./index.html} $out/lib/ghostty-web/static/index.html
      cp ${ghosttyWebPkg}/dist/ghostty-web.js $out/lib/ghostty-web/static/
      cp ${ghosttyWebPkg}/ghostty-vt.wasm $out/lib/ghostty-web/static/

      # Create wrapper with --chdir (CRITICAL for ESM resolution)
      # ESM ignores NODE_PATH; must set CWD to directory containing node_modules
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/ghostty-web-server \
        --add-flags "$out/lib/ghostty-web/server.js" \
        --chdir "$out/lib/ghostty-web" \
        --set GHOSTTY_WEB_STATIC "$out/lib/ghostty-web/static" \
        --set GHOSTTY_WEB_WASM "$out/lib/ghostty-web/static/ghostty-vt.wasm" \
        --set NODE_ENV "production"

      runHook postInstall
    '';

    meta = {
      description = "Ghostty web terminal server for Konductor";
      homepage = "https://github.com/coder/ghostty-web";
      license = lib.licenses.mit;
      mainProgram = "ghostty-web-server";
    };
  };

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Package list for inclusion in devshells/system packages
  packages = [ ghosttyWebServer ];

  # Server package for direct reference (used by NixOS module)
  server = ghosttyWebServer;

  # Individual components for testing/debugging
  components = {
    inherit ghosttyWebPkg;
  };

  # No shell hook needed - service is systemd-managed
  shellHook = "";

  # Environment variables (for manual testing in devshell)
  env = {
    GHOSTTY_WEB_STATIC = "${ghosttyWebServer}/lib/ghostty-web/static";
    GHOSTTY_WEB_WASM = "${ghosttyWebServer}/lib/ghostty-web/static/ghostty-vt.wasm";
  };
}
