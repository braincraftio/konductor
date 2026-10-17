# src/programs/forgejo/default.nix
# Forgejo self-hosted git forge tooling
#
# Provides:
#   - server: Forgejo git forge server (nixpkgs)
#   - cli: forgejo-cli for the Forgejo API (nixpkgs)
#   - runner: BrainCraft forgejo-runner fork (runner.nix), or null
#
# The runner exists only when the forgejo-runner-src flake input is declared.
# Flake inputs are fetched lazily and nothing references the input when it is
# absent, so commenting the input out in flake.nix disables the fork across
# every consumer (devshell, qcow2 module, flake package) with no other edit.

{
  pkgs,
  lib,
  inputs,
}:

let
  # Forgejo packages from nixpkgs
  forgejoServer = pkgs.forgejo; # v13.x - current stable
  forgejoCli = pkgs.forgejo-cli; # v0.3.x - API CLI

  forgejoRunner =
    if inputs ? forgejo-runner-src then
      pkgs.callPackage ./runner.nix { src = inputs.forgejo-runner-src; }
    else
      null;

  runnerPackages = lib.optional (forgejoRunner != null) forgejoRunner;
in
{
  # Direct package exports (runner is null when the fork input is absent)
  runner = forgejoRunner;
  server = forgejoServer;
  cli = forgejoCli;

  # Full package set
  packages = [
    forgejoServer
    forgejoCli
  ]
  ++ runnerPackages;

  # Server-only (for hosting instances)
  serverPackages = [
    forgejoServer
  ];

  # Runner-only (for CI/CD agents); empty when the fork input is absent
  inherit runnerPackages;

  # CLI-only (for development/scripting)
  cliPackages = [
    forgejoCli
  ];

  # Shell hook for Forgejo environment
  shellHook = ''
    # Forgejo environment hints
    if command -v forgejo-runner &>/dev/null; then
      export FORGEJO_RUNNER_AVAILABLE=1
    fi
  '';

  # Environment variables
  env = {
    # Runner config location - deterministic path for runner user (uid 1003)
    FORGEJO_RUNNER_CONFIG = "/home/runner/.config/forgejo-runner/config.yaml";
  };
}
