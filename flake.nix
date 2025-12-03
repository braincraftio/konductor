# flake.nix
# Konductor multi-target development orchestration
# Orchestration layer - implementation in src/

{
  description = "Konductor: Polyglot Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs = { nixpkgs, flake-utils, ... }@inputs:
    let
      # Import overlays
      overlays = import ./src/overlays {
        inherit (nixpkgs) lib;
        inherit (inputs) nixpkgs-unstable;
      };

    in

    # Per-system outputs (devShells, packages)
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ inputs.rust-overlay.overlays.default ] ++ overlays;
            config.allowUnfree = true;
          };

          # Import versions for devshells
          versions = import ./src/lib/versions.nix;

          # Import programs (neovim, tmux)
          programs = import ./src/programs { inherit pkgs inputs; inherit (nixpkgs) lib; };

          # Import devshells (single source of truth for all development shells)
          devshells = import ./src/devshells {
            inherit pkgs inputs versions programs;
            inherit (nixpkgs) lib;
          };

          # OCI container (Linux-only)
          oci = import ./src/oci {
            inherit pkgs inputs;
            inherit (nixpkgs) lib;
            inherit (inputs.nix2container.packages.${system}) nix2container;
          };

          # QCOW2 VM (Linux-only)
          qcow2 = import ./src/qcow2 {
            inherit pkgs inputs system;
            inherit (nixpkgs) lib;
            inherit (inputs) nixos-generators;
          };

        in
        {
          # Development shells from src/devshells
          devShells = {
            inherit (devshells) default python go node rust dev full;
          };

          # Packages (build outputs, not shells)
          packages = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            # OCI and QCOW2 are Linux-only
            oci = oci.image;
            qcow2 = qcow2.image;
          };
        }
      )

    # Cross-system outputs (modules, overlays)
    // {
      overlays.default = nixpkgs.lib.composeManyExtensions overlays;

      # NixOS module - recognized by both Nix and Lix
      nixosModules = {
        konductor = import ./src/modules/nixos.nix;
        default = import ./src/modules/nixos.nix;
      };

      # Home Manager module
      homeModules = {
        konductor = import ./src/modules/home-manager.nix;
        default = import ./src/modules/home-manager.nix;
      };

      # nix-darwin module - recognized by both Nix and Lix
      darwinModules = {
        konductor = import ./src/modules/darwin.nix;
        default = import ./src/modules/darwin.nix;
      };
    };
}
