# src/programs/forgejo/default.nix
# Forgejo self-hosted git forge tooling
#
# Provides:
#   - forgejo-server: Self-hosted git forge server
#   - forgejo-runner: CI/CD runner (forked with include_server_host)
#   - forgejo-cli: Command-line interface for Forgejo API
#
# Usage:
#   CI runners: Include in ci devshell for self-hosted CI/CD
#   Development: forgejo-cli for API interactions

{ pkgs, ... }:

let
  # Forgejo packages from nixpkgs
  forgejoServer = pkgs.forgejo; # v13.x - current stable
  forgejoCli = pkgs.forgejo-cli; # v0.3.x - API CLI

  # Forked runner with include_server_host support
  # Source: git.braincraft.io/BrainCraft/runner
  # Feature: container.include_server_host prepends server hostname to workspace path
  #          Default: /workspace/owner/repo
  #          Enabled: /workspace/git.example.com/owner/repo
  forgejoRunnerSrc = pkgs.fetchzip {
    url = "https://git.braincraft.io/BrainCraft/runner/archive/d97b4afd9f104b414d96547bde0cd79b19f4e766.tar.gz";
    hash = "sha256-S7v0dFlIewtlLMOu6qeafOfudNoKoCwNdw9U/XCjrls=";
  };
  forgejoRunner = pkgs.forgejo-runner.overrideAttrs (oldAttrs: {
    src = forgejoRunnerSrc;
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
