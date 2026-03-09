# src/overlays/code-server.nix
# Pre-built code-server binary overlay
#
# Replaces the nixpkgs code-server (which builds VS Code from source via yarn,
# taking 2-4 hours) with a pre-built standalone release tarball from GitHub.
# This is the same pattern nixpkgs uses for VS Code itself (vscode.nix).
#
# code-server publishes standalone tarballs at:
#   https://github.com/coder/code-server/releases
#
# To update:
#   1. Change version
#   2. Run: nix-prefetch-url --unpack <new-url>
#   3. Convert: nix hash to-sri --type sha256 <hash>
#   4. Update hash

_final: prev:

let
  version = "4.109.5";

  src = prev.fetchurl {
    url = "https://github.com/coder/code-server/releases/download/v${version}/code-server-${version}-linux-amd64.tar.gz";
    hash = "sha256-8HNw/Tgy2mbPCCIE6IfzQh5INYWBy6Hbe4fOIt+pFuY=";
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

    buildInputs = with prev; [
      nodejs
      stdenv.cc.cc.lib
      zlib
    ];

    dontBuild = true;

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
