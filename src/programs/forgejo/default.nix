# src/programs/forgejo/default.nix
# Forgejo self-hosted git forge tooling
#
# Provides:
#   - forgejo-server: Self-hosted git forge server
#   - forgejo-runner: CI/CD runner (forked with workspace isolation)
#   - forgejo-cli: Command-line interface for Forgejo API
#
# Usage:
#   CI runners: Include in ci devshell for self-hosted CI/CD
#   Development: forgejo-cli for API interactions
#
# Runner Fork Features (git.braincraft.io/BrainCraft/runner):
#   - container.include_server_host: prepends server hostname to workspace path
#   - container.workspace_repo: clones workspace repo for tooling inheritance
#   - Collision isolation via /workspace/<random>/<host>/<owner>/<repo>
#
# Update runner: nix flake update forgejo-runner-src

{ pkgs, inputs, ... }:

let
  # Forgejo packages from nixpkgs
  forgejoServer = pkgs.forgejo; # v13.x - current stable
  forgejoCli = pkgs.forgejo-cli; # v0.3.x - API CLI

  # Forked runner from flake input (auto-updated via nix flake update)
  forgejoRunner = pkgs.forgejo-runner.overrideAttrs (oldAttrs: {
    src = inputs.forgejo-runner-src;
    vendorHash = "sha256-fvSiEIE4XSJ8Ot4Tcmt8chD11fHVsECD2/8xrgIKhJs=";
  });

in
{
  # Direct package exports (for systemd services, etc.)
  runner = forgejoRunner;
  server = forgejoServer;
  cli = forgejoCli;

  # Full package set (server + runner + cli)
  packages = [
    forgejoServer
    forgejoRunner
    forgejoCli
  ];

  # Server-only (for hosting instances)
  serverPackages = [
    forgejoServer
  ];

  # Runner-only (for CI/CD agents)
  runnerPackages = [
    forgejoRunner
  ];

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
