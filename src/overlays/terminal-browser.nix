# src/overlays/terminal-browser.nix
# terminal-browser: Chromium rendered inside kitty-graphics-protocol terminals.
# Pre-built binary from zenbu-labs/terminal-browser GitHub releases.
#
# Cannot use pkgs.electron: pixel.node (Rust cdylib native addon) binds against
# the exact Electron/Node N-API ABI of the zenbu-labs/electron-releases fork.
# Substituting nixpkgs' Electron produces ABI mismatch crashes at runtime.
#
# Requires a terminal supporting the kitty graphics protocol (ghostty, kitty,
# wezterm, vscode). Does not work inside ttyd/xterm.js.
#
# Sandbox (Linux): Electron's Chromium sandbox requires one of:
#   1. Unprivileged user namespaces enabled (NixOS default, most distros)
#   2. NixOS security.wrappers for setuid chrome-sandbox
#   3. AppArmor profile via `terminal-browser setup` (Ubuntu 24.04+)
#
# Version bump procedure:
#   1. src/lib/versions.nix terminal-browser.version
#   2. Update hashes below (nix reports correct hash on mismatch)

let
  versions = import ../lib/versions.nix;
in

_final: prev:
let
  version = versions.terminal-browser.version;

  srcs = {
    x86_64-linux = {
      url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-linux-x64.tar.gz";
      hash = "sha256-vjZ+fZQsW2/jmjJxBejcPkQS2SR0riukKrBWRS7E4sQ=";
    };
    aarch64-linux = {
      url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-linux-arm64.tar.gz";
      hash = "sha256-cVD6l0YNmDS/1r8eSnH25TitvH/S7Wh50EV/zMoyPUY=";
    };
    aarch64-darwin = {
      url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-darwin-arm64.tar.gz";
      hash = "sha256-hnWPfDegDzBDC1lHneAga6/DhdMZa0DXx8ZbVABk08A=";
    };
    x86_64-darwin = {
      url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-darwin-x64.tar.gz";
      hash = "sha256-3xhxbLa6jHhG4E092/YpGkUNFSmtBp3jM6wXsksfAcs=";
    };
  };

  platformSrc = srcs.${prev.stdenv.hostPlatform.system} or null;
  sandboxName = "terminal-browser-chrome-sandbox";
in
if platformSrc == null then
  { }
else
  {
    terminal-browser = prev.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "terminal-browser";
      inherit version;

      src = prev.fetchurl {
        inherit (platformSrc) url hash;
      };

      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;

      # Do not run autoPatchelf automatically. pixel.node is a Rust cdylib
      # loaded via Node's native-addon dlopen; agent-browser may be statically
      # linked. Blanket patching corrupts their load paths. postFixup invokes
      # autoPatchelf targeting only the Electron binary directory.
      dontAutoPatchelf = true;

      # Darwin: disable entire fixup phase to preserve ad-hoc codesigning on
      # Electron.app, agent-browser, and native-scroll-helper. Any binary
      # mutation (strip, patchshebangs, rpath shrinking) invalidates the
      # signature causing Gatekeeper killed:9 at runtime.
      dontFixup = prev.stdenv.hostPlatform.isDarwin;

      # Musl-linked SONAMEs ship alongside glibc prebuilds in vendored Node
      # native addons. autoPatchelf cannot resolve them on glibc hosts and
      # hard-fails without this. They are not loaded at runtime.
      autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.*" ];

      nativeBuildInputs = [
        prev.makeWrapper
      ]
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
        prev.autoPatchelfHook
      ];

      buildInputs = prev.lib.optionals prev.stdenv.hostPlatform.isLinux (
        with prev;
        [
          nss
          gtk3
          alsa-lib
          mesa
          libdrm
          at-spi2-atk
          cups
          pango
          cairo
          nspr
          expat
          libxkbcommon
          dbus
          libx11
          libxcb
          libxcomposite
          libxdamage
          libxrandr
          libxshmfence
          libxext
          libxfixes
        ]
      );

      # Patch paths.ts to use a fixed APP_DIR_NAME independent of the nix
      # store path. Without this, every rebuild changes the store path hash
      # which changes the data directory, orphaning cookies/sessions/DB.
      # The fixed name "terminal-browser-nix" is stable across all rebuilds.
      postPatch = ''
        if [ -f terminal-browser/cli/dist/main.js ]; then
          substituteInPlace terminal-browser/cli/dist/main.js \
            --replace-quiet \
              'const suffix=crypto.createHash("sha256").update(INSTALL_ROOT.root).digest("hex").slice(0,8)' \
              'const suffix="nix"'
        fi
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/terminal-browser $out/bin
        cp -a terminal-browser/. $out/lib/terminal-browser/

        chmod +x $out/lib/terminal-browser/bin/terminal-browser
        chmod +x $out/lib/terminal-browser/agent-browser/bin/agent-browser || true
        if [ -f $out/lib/terminal-browser/electron/electron ]; then
          chmod +x $out/lib/terminal-browser/electron/electron
        fi
        if [ -f $out/lib/terminal-browser/bin/native-scroll-helper ]; then
          chmod +x $out/lib/terminal-browser/bin/native-scroll-helper
        fi

        # Wrapper provides:
        # - TERMINAL_BROWSER_DIST_ROOT: asset resolution for the CLI
        # - CHROME_DEVEL_SANDBOX: runtime fallback check for setuid wrapper
        #   at /run/wrappers/bin/ (NixOS security.wrappers), falls back to
        #   unprivileged bundled binary (matches chromium/default.nix pattern)
        # - Upgrade interception: self-update is incompatible with nix store
        makeWrapper $out/lib/terminal-browser/bin/terminal-browser $out/bin/terminal-browser \
          --set TERMINAL_BROWSER_DIST_ROOT $out/lib/terminal-browser \
          --run 'if [ -x "/run/wrappers/bin/${sandboxName}" ]; then export CHROME_DEVEL_SANDBOX="/run/wrappers/bin/${sandboxName}"; else export CHROME_DEVEL_SANDBOX="${placeholder "out"}/lib/terminal-browser/electron/chrome-sandbox"; fi' \
          --run 'case "$1" in upgrade) echo "terminal-browser is managed by Nix." >&2; exit 1;; esac'

        runHook postInstall
      '';

      # Targeted autoPatchelf: patch only the Electron binary and shared
      # libraries. pixel.node (browser/native/) and agent-browser are never
      # in the patch scope, so no backup/restore needed.
      postFixup = prev.lib.optionalString prev.stdenv.hostPlatform.isLinux ''
        autoPatchelf $out/lib/terminal-browser/electron
      '';

      passthru = {
        inherit sandboxName;
        sandboxExecutableName = sandboxName;

        tests = {
          # Verify pixel.node links only against standard glibc libs and
          # needs no patching. If upstream adds a new dynamic dependency,
          # this fails the build instead of failing silently at runtime.
          pixel-node-deps =
            prev.runCommand "check-pixel-node-deps"
              {
                nativeBuildInputs = [ prev.patchelf ];
              }
              ''
                needed=$(patchelf --print-needed ${finalAttrs.finalPackage}/lib/terminal-browser/browser/native/pixel.node 2>/dev/null || true)
                for lib in $needed; do
                  case "$lib" in
                    libc.so*|libm.so*|libstdc++.so*|libgcc_s.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*) ;;
                    *) echo "unexpected dependency: $lib" >&2; exit 1 ;;
                  esac
                done
                touch $out
              '';
          version =
            prev.runCommand "check-terminal-browser-version"
              {
                nativeBuildInputs = [ finalAttrs.finalPackage ];
                meta.timeout = 60;
              }
              ''
                terminal-browser --version > /dev/null && touch $out
              '';
        };
      };

      meta = {
        description = "Chromium browser rendered inside terminal via kitty graphics protocol";
        homepage = "https://github.com/zenbu-labs/terminal-browser";
        license = prev.lib.licenses.mit;
        sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
        mainProgram = "terminal-browser";
        platforms = prev.lib.attrNames srcs;
      };
    });
  }
