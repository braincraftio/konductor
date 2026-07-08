# src/packages/trzsz.nix
# trzsz-go — trz / tsz / trzsz binaries (server side of the trzsz protocol)
#
# trzsz is a zmodem-style file-transfer protocol carried inside the terminal
# byte stream (no side channel), which is why it works through
# ttyd → WebSocket → browser. ttyd's frontend compiles in the trzsz JS addon
# (browser = "local" side: file picker, drag-drop, downloads); the VM needs
# trz (upload to VM) and tsz (download from VM) on PATH.
#
# Packaged in-repo because nixpkgs (stable and unstable) ships only
# trzsz-ssh (tssh) — the local ssh client, not the server-side binaries.
# Requires Go >= 1.25 (go.mod directive); default buildGoModule satisfies
# this and the Go 1 compatibility promise covers future default bumps.
#
# checkPhase note: upstream's network/Docker-dependent tests live in the
# trzsz/ library package; subPackages scopes both build and check to cmd/*
# (no tests), so doCheck stays at its default.
#
# Upstream: https://github.com/trzsz/trzsz-go
# Invoke with: pkgs.callPackage ./trzsz.nix { }

{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
  nix-update-script,
}:

buildGoModule (finalAttrs: {
  pname = "trzsz-go";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "trzsz";
    repo = "trzsz-go";
    tag = "v${finalAttrs.version}";
    hash = "sha256-CokZAXT61UKSsKnzE5mPMdAZecGX/8mgDkG4yDSat5M=";
  };

  vendorHash = "sha256-eqQ5PpHNLp2QebC6fZcVYT9hHAeXfM6GLiji4WzGSRQ=";

  subPackages = [
    "cmd/trz"
    "cmd/tsz"
    "cmd/trzsz"
  ];

  # Pure Go — static binaries, no libc dependency
  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  # Hook default derives the program from pname (trzsz-go), which names no
  # binary in $out/bin — pin to mainProgram. `trzsz --version` → "trzsz go 1.2.0"
  versionCheckProgram = "${placeholder "out"}/bin/${finalAttrs.meta.mainProgram}";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "trzsz (trz / tsz) terminal file transfer, Go implementation";
    homepage = "https://trzsz.github.io/go";
    changelog = "https://github.com/trzsz/trzsz-go/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    mainProgram = "trzsz";
    platforms = lib.platforms.all;
  };
})
