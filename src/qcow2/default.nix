# src/qcow2/default.nix
# QCOW2 VM build using nixos-generators
#
# Self-hosting capable: can build konductor OCI, QCOW2, and run full CI

{ pkgs, lib, nixos-generators, system, ... }:

let
  versions = import ../lib/versions.nix;
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;

  # Config provides wrapped linters/formatters with hermetic configuration
  # This is REQUIRED - unwrapped tools violate configuration standards
  config = import ../config { inherit pkgs lib versions; };

  # Import packages with wrapped config (hermetic linters/formatters)
  devshellPackages = import ../packages {
    inherit pkgs lib versions config;
  };

  # Self-hosting packages for building konductor artifacts
  selfHostingPackages = with pkgs; [
    # Container tooling
    docker
    docker-compose
    docker-buildx
    buildkit

    # VM/QCOW2 tooling
    qemu_kvm
    qemu-utils
    libvirt
    virt-manager

    # Cloud-init ISO creation
    cdrkit

    # CI/CD essentials
    git
    gh
    gnumake
  ];

in
{
  # QCOW2 VM image
  image = nixos-generators.nixosGenerate {
    inherit system;
    format = "qcow";
    modules = [
      {
        # Basic system configuration
        # stateVersion from src/lib/versions.nix nixos.stateVersion
        system.stateVersion = versions.nixos.stateVersion;
        networking.hostName = "konductor";
        networking.useNetworkd = true;
        systemd.network.enable = true;
        systemd.network.networks."10-ethernet" = {
          matchConfig.Type = "ether";
          networkConfig.DHCP = "yes";
        };

        # Users
        users.users.kc2 = {
          isNormalUser = true;
          inherit (users.kc2) uid home;
          description = users.kc2.gecos;
          extraGroups = [ "wheel" "docker" "libvirtd" "kvm" ];
        };

        users.users.kc2admin = {
          isNormalUser = true;
          inherit (users.kc2admin) uid home;
          description = users.kc2admin.gecos;
          extraGroups = [ "wheel" "docker" "libvirtd" "kvm" ];
        };

        # Sudo without password
        security.sudo.wheelNeedsPassword = false;

        # Packages: devshell defaults + self-hosting tools
        environment.systemPackages = devshellPackages.default
          ++ selfHostingPackages
          ++ [ pkgs.cachix ];

        # Environment variables from centralized configuration
        environment.variables = lib.mapAttrs (_name: value: lib.mkForce value) env;

        # Services configuration
        services = {
          # SSH for VM access
          openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "yes";
              PasswordAuthentication = true;
            };
          };

          # QEMU guest agent for VM management
          qemuGuest.enable = true;

          # Cloud-init for dynamic configuration
          cloud-init = {
            enable = true;
            network.enable = true;
          };
        };

        # Docker for container builds
        virtualisation.docker = {
          enable = true;
          enableOnBoot = true;
        };

        # Libvirt for nested VM builds
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            runAsRoot = true;
            swtpm.enable = true;
          };
        };

        # Disk size for VM (larger for self-hosting)
        virtualisation.diskSize = lib.mkDefault (50 * 1024); # 50GB

        # Virtio drivers for performance
        boot.initrd.availableKernelModules = [
          "virtio_net"
          "virtio_pci"
          "virtio_mmio"
          "virtio_blk"
          "virtio_scsi"
          "virtio_balloon"
          "virtio_console"
          "9p"
          "9pnet_virtio"
        ];

        # Spice/QEMU guest tools for clipboard, display, etc.
        services.spice-vdagentd.enable = true;

        # Nix configuration
        nix = {
          settings = {
            experimental-features = [ "nix-command" "flakes" ];
            auto-optimise-store = true;
            accept-flake-config = true;
            trusted-users = [ "root" "kc2" "kc2admin" ];
            substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
            trusted-substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };
          # Pre-configured flake registry
          registry.konductor = {
            from = { type = "indirect"; id = "konductor"; };
            to = { type = "github"; owner = "braincraftio"; repo = "konductor"; };
          };
        };
      }
    ];
  };
}
