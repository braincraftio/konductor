# src/devshells/konductor.nix
# Konductor self-hosting shell — extends full with build and CI tooling
#
# Accumulative hierarchy: base → full → konductor → frontend
#
# Adds to full:
#   - VM build tools (qemu, libvirt, libguestfs, OVMF)
#   - ttyd web terminal with Catppuccin Frappé theme
#   - Forgejo runner and CLI for CI/CD
#   - C++ stdlib for native extensions
#
# Package composition defined in: ../packages/
# SSH config from: ../config/shell/ssh.nix
# OpenCode theme from: ../config/opencode/
# Atuin shell history from: ../config/shell/atuin.nix

{
  fullShell,
  pkgs,
  packages,
  versions,
  programs,
  config,
  ...
}:

let
  langs = versions.languages;
  inherit (packages) konductor;
in

fullShell.overrideAttrs (old: {
  name = "konductor";

  # Konductor-specific additions on top of full
  nativeBuildInputs =
    old.nativeBuildInputs
    # Self-hosting: VM build tools (qemu, libvirt, libguestfs, etc.)
    ++ konductor.packages
    # ttyd web terminal with Catppuccin Frappé theme
    ++ programs.ttyd.packages
    # Forgejo CI/CD runner and CLI
    ++ programs.forgejo.runnerPackages
    # C++ stdlib for native extensions
    ++ [ pkgs.stdenv.cc.cc.lib ];

  shellHook = ''
    # Runtime libraries (dynamic: appends to existing LD_LIBRARY_PATH)
    # Prepended before old.shellHook so LD_LIBRARY_PATH is available early
    export LD_LIBRARY_PATH="${
      pkgs.lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.xz
        pkgs.zstd
      ]
    }"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  ''
  + old.shellHook
  + ''
    # Docker host (dynamic, uses default if not set)
    DOCKER_HOST="''${DOCKER_HOST:-unix:///var/run/docker.sock}"

    # Konductor self-hosting
    ${konductor.shellHook}

    # Forgejo CI/CD (conditional)
    ${programs.forgejo.shellHook}

    if [ -z "''${KONDUCTOR_QUIET:-}" ]; then
      echo "konductor: py${langs.python.display} go${langs.go.display} node${langs.node.display} rust${langs.rust.display} k0s${versions.kubernetes.k0s.display}"
    fi

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env =
    old.env
    // {
      # Shell identity
      KONDUCTOR_SHELL = "konductor";
      KONDUCTOR_SKIP_BANNER = "1";
      # Docker
      DOCKER_BUILDKIT = "1";
    }
    // (konductor.env pkgs)
    // programs.forgejo.env;
})
