# src/qcow2/default.nix
# QCOW2 VM build using nixos-generators

{ pkgs, lib, nixos-generators, system, ... }:

let
  versions = import ../lib/versions.nix;
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;

  # Import packages from src/packages/
  devshellPackages = import ../packages {
    inherit pkgs lib versions;
  };

in
{
  # QCOW2 VM image
  image = nixos-generators.nixosGenerate {
    inherit system;
    format = "qcow";
    modules = [
      {
        # Basic system configuration
        system.stateVersion = "25.11";
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
          extraGroups = [ "wheel" ];
        };

        users.users.kc2admin = {
          isNormalUser = true;
          inherit (users.kc2admin) uid home;
          description = users.kc2admin.gecos;
          extraGroups = [ "wheel" ];
        };

        # Sudo without password
        security.sudo.wheelNeedsPassword = false;

        # Packages from devshellPackages.default (no languages, no IDE)
        environment.systemPackages = devshellPackages.default
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

        # Disk size for VM
        virtualisation.diskSize = lib.mkDefault (20 * 1024); # 20GB

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
