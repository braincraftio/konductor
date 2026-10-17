# src/programs/forgejo/runner.nix
# BrainCraft forgejo-runner fork (pre-release): workspace isolation features
#   - container.include_server_host: prepends server hostname to workspace path
#   - container.workspace_repo: clones workspace repo for tooling inheritance
#   - Collision isolation via /workspace/<random>/<host>/<owner>/<repo>
#
# Built from the forgejo-runner-src flake input; version and vendorHash are
# the versions.forgejo-runner release record. buildGoModule is used directly
# (not overrideAttrs on nixpkgs forgejo-runner): overrideAttrs does not
# reliably propagate src changes for buildGoModule.

{
  buildGoModule,
  git,
  src,
}:

let
  versions = import ../../lib/versions.nix;
in
buildGoModule {
  pname = "forgejo-runner";
  inherit (versions.forgejo-runner) version vendorHash;
  inherit src;
  proxyVendor = true; # Fetch deps via Go proxy, ignore stale vendor/
  subPackages = [ "." ];
  ldflags = [
    "-s"
    "-w"
    "-X"
    "code.forgejo.org/forgejo/runner/v12/internal/pkg/ver.version=v${versions.forgejo-runner.version}"
  ];
  nativeBuildInputs = [ git ];
  doCheck = false;
  # Binary builds as "runner" from directory name; rename to expected "forgejo-runner"
  postInstall = ''
    mv $out/bin/runner $out/bin/forgejo-runner
  '';
  meta.mainProgram = "forgejo-runner";
}
