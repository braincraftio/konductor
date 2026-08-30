# src/overlays/code-server.nix
# Pre-built code-server binary overlay
#
# Replaces the nixpkgs code-server (which builds VS Code from source via yarn,
# taking 2-4 hours) with a pre-built standalone release tarball from GitHub.
# Aligned with the nixpkgs VSCode pattern (generic.nix / buildVscode):
#   - autoPatchelfHook for ELF patching
#   - buildInputs provide native libs autoPatchelf needs to resolve
#   - preFixup removes musl-only prebuilds (we run glibc) and the MSAL
#     desktop auth extension (headless code-server uses token auth, not
#     native SSO via GTK/webkit/dbus)
#
# code-server publishes standalone tarballs at:
#   https://github.com/coder/code-server/releases
#
# To update:
#   1. Change version
#   2. Run: nix-prefetch-url <new-url>  (NOT --unpack; fetchurl hashes the raw tarball)
#   3. Update hash with the sha256 nix reports on mismatch (already SRI format)

_final: prev:
if !(prev.stdenv.hostPlatform.isLinux && prev.stdenv.hostPlatform.isx86_64) then
  { }
else
  let
    version = "4.109.5";

    src = prev.fetchurl {
      url = "https://github.com/coder/code-server/releases/download/v${version}/code-server-${version}-linux-amd64.tar.gz";
      hash = "sha256-Fcp0cuRSLyFOARQ2c1WZOFNlcdcVLF/KPLQpZueaaIs=";
    };
  in
  {
    code-server = prev.stdenv.mkDerivation {
      pname = "code-server";
      inherit version src;

      sourceRoot = "code-server-${version}-linux-amd64";

      nativeBuildInputs = with prev; [
        autoPatchelfHook
        makeWrapper
      ];

      # Native libs that autoPatchelf resolves against.
      # Mirrors buildVscode buildInputs for the subset code-server actually links.
      buildInputs = with prev; [
        nodejs
        stdenv.cc.cc.lib # libstdc++
        zlib
        libsecret # libsecret-1.so (keyring integration)
        libx11 # libX11.so.6 (msal-node-runtime.node)
        libxkbfile # libxkbfile.so.1 (native keyboard module)
        nss # libnss3.so (crypto)
        nspr # libnspr4.so
        alsa-lib # libasound.so.2
        systemdLibs # libudev, libsystemd
        dbus # libdbus-1.so.3
        util-linux.lib # libuuid.so.1
        curl # libcurl.so.4
        openssl # libcrypto.so.3, libssl.so.3
      ];

      dontBuild = true;

      preFixup = ''
        # Remove musl-only prebuilds — we run glibc, these .node files would
        # never be loaded but autoPatchelf fails trying to resolve musl libc.
        find $out -name '*.musl.node' -delete
        find $out -path '*linux-x64-musl*' -name '*.node' -delete

        # Remove MSAL desktop-auth native extension — requires GTK3, webkit2gtk,
        # libsoup, gobject, glib (heavy GUI stack). code-server is headless and
        # uses password/token auth, never native desktop SSO.
        rm -rf $out/lib/code-server/lib/vscode/extensions/microsoft-authentication/dist/libmsalruntime.so
        rm -rf $out/lib/code-server/lib/vscode/extensions/microsoft-authentication/dist/msal-node-runtime.node
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/code-server $out/bin
        cp -r . $out/lib/code-server/

        makeWrapper ${prev.nodejs}/bin/node $out/bin/code-server \
          --add-flags "$out/lib/code-server/out/node/entry.js"

        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "VS Code in the browser (pre-built binary)";
        homepage = "https://github.com/coder/code-server";
        license = licenses.mit;
        platforms = [ "x86_64-linux" ];
        mainProgram = "code-server";
      };
    };
  }
