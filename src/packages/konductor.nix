# src/packages/konductor.nix
# Self-hosting packages for building konductor artifacts
#
# These are NOT included in the QCOW2 image to keep it lean.
# Instead, users run `nix develop konductor#konductor` inside the VM
# to get these tools on-demand from the Nix cache.
#
# Includes:
#   - Container tooling (docker, buildkit)
#   - VM/QCOW2 tooling (qemu, libvirt)
#   - Cloud-init ISO creation
#   - CI/CD essentials

{ pkgs }:

{
  packages = with pkgs; [
    # Container tooling
    docker
    docker-compose
    docker-buildx
    buildkit
    skopeo
    crane

    # VM/QCOW2 tooling
    qemu_kvm
    qemu-utils
    libvirt
    virt-manager

    # Cloud-init ISO creation
    cdrkit

    # CI/CD essentials
    gnumake
    cachix
  ];

  shellHook = ''
    # Konductor self-hosting environment
    export DOCKER_HOST="''${DOCKER_HOST:-unix:///var/run/docker.sock}"
  '';

  env = {
    DOCKER_BUILDKIT = "1";
  };
}
