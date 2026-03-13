# flake.nix
# Konductor multi-target development orchestration
# Orchestration layer - implementation in src/

{
  description = "Konductor: Polyglot Development Environment";

  # ===========================================================================
  # Flake Inputs
  # ===========================================================================
  # VERSION SYNC: nixpkgs channel version is defined in src/lib/versions.nix
  # Flake inputs cannot import nix files, so version must be duplicated here.
  # When updating nixos.channel in versions.nix, also update:
  #   - nixpkgs.url branch below
  #   - nixvim.url branch below (must match nixpkgs)
  #   - home-manager.url branch below (must match nixpkgs)
  # ===========================================================================
  inputs = {
    # NixOS 25.11 - sync with src/lib/versions.nix nixos.channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nuschtosSearch = {
      url = "github:NuschtOS/search";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ixx = {
      url = "github:NuschtOS/ixx";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixlib.url = "github:nix-community/nixpkgs.lib";

    nix2container = {
      url = "git+https://github.com/nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-generators removed - using native nixpkgs image building
    # (nixos-generators deprecated in NixOS 25.05, mainlined to nixpkgs)

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Must match nixpkgs branch - sync with src/lib/versions.nix nixos.channel
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        nuschtosSearch.follows = "nuschtosSearch";
      };
    };

    # Must match nixpkgs branch - sync with src/lib/versions.nix nixos.channel
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Catppuccin themes for k9s and other applications
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Forked Forgejo runner with workspace isolation
    # Source: git.braincraft.io/BrainCraft/runner
    # Update: nix flake update forgejo-runner-src
    forgejo-runner-src = {
      url = "git+https://git.braincraft.io/BrainCraft/runner";
      flake = false;
    };

    systems.url = "github:nix-systems/default";
  };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    { nixpkgs, flake-utils, ... }@inputs:
    let
      # Import overlays
      overlays = import ./src/overlays {
        inherit (nixpkgs) lib;
        inherit (inputs) nixpkgs-unstable;
      };

    in

    # Per-system outputs (devShells, packages)
    flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ inputs.rust-overlay.overlays.default ] ++ overlays;
            config.allowUnfree = true;
          };

          # Import versions for devshells
          versions = import ./src/lib/versions.nix;

          # Import programs (neovim, tmux)
          programs = import ./src/programs {
            inherit pkgs inputs;
            inherit (nixpkgs) lib;
          };

          # Import devshells (single source of truth for all development shells)
          devshells = import ./src/devshells {
            inherit
              pkgs
              inputs
              versions
              programs
              ;
            inherit (nixpkgs) lib;
          };

          # OCI container (Linux-only)
          oci = import ./src/oci {
            inherit pkgs inputs;
            inherit (nixpkgs) lib;
            inherit (inputs.nix2container.packages.${system}) nix2container;
          };

          # QCOW2 VM (Linux-only)
          # Uses native nixpkgs image building (no nixos-generators)
          qcow2 = import ./src/qcow2 {
            inherit
              pkgs
              nixpkgs
              inputs
              system
              versions
              programs
              devshells
              ;
            inherit (nixpkgs) lib;
          };

        in
        {
          # Development shells from src/devshells
          # Cross-platform shells available everywhere
          # Linux-only shells (konductor, ci, frontend) conditionally included
          devShells = {
            inherit (devshells)
              default
              python
              go
              node
              rust
              dev
              full
              ;
          }
          // pkgs.lib.optionalAttrs (pkgs.stdenv.system == "x86_64-linux") {
            # x86_64-linux only: requires libguestfs-appliance (qemu_kvm, libvirt, virt-manager, etc.)
            # frontend extends konductor, so it's also Linux-only
            inherit (devshells) konductor ci frontend;
          };

          # Packages (build outputs, not shells)
          packages =
            pkgs.lib.optionalAttrs pkgs.stdenv.isLinux
              {
                # OCI is Linux-only (Docker/podman)
                oci = oci.image;
              }
            // pkgs.lib.optionalAttrs (pkgs.stdenv.system == "x86_64-linux") {
              # qcow2 requires libguestfs-appliance which only supports x86_64-linux
              qcow2 = qcow2.image;
            };
        }
      )

    # Cross-system outputs (modules, overlays, nixosConfigurations)
    // {
      overlays.default = nixpkgs.lib.composeManyExtensions overlays;

      # NixOS configurations for live rebuilds on running VMs
      # Usage: sudo nixos-rebuild switch --flake .#konductor
      nixosConfigurations.konductor =
        let
          system = "x86_64-linux";
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ inputs.rust-overlay.overlays.default ] ++ overlays;
            config.allowUnfree = true;
          };
          versions = import ./src/lib/versions.nix;
          programs = import ./src/programs {
            inherit pkgs inputs;
            inherit (nixpkgs) lib;
          };
          devshells = import ./src/devshells {
            inherit pkgs inputs versions programs;
            inherit (nixpkgs) lib;
          };
          qcow2 = import ./src/qcow2 {
            inherit pkgs nixpkgs inputs system versions programs devshells;
            inherit (nixpkgs) lib;
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ qcow2.konductorModule ];
        };

      # NixOS module - standard flake output per `nix flake check --help`
      nixosModules = {
        konductor = import ./src/modules/nixos.nix;
        default = import ./src/modules/nixos.nix;
      };

      # Home Manager module - convention from nix-community/home-manager
      # Not a standard flake output - `nix flake check` warns "unknown flake output"
      # This is expected and harmless; home-manager recognizes this output
      homeManagerModules = {
        konductor = import ./src/modules/home-manager.nix;
        default = import ./src/modules/home-manager.nix;
      };

      # nix-darwin module - convention from LnL7/nix-darwin
      # Not a standard flake output - `nix flake check` warns "unknown flake output"
      # This is expected and harmless; nix-darwin recognizes this output
      darwinModules = {
        konductor = import ./src/modules/darwin.nix;
        default = import ./src/modules/darwin.nix;
      };
    };
}
