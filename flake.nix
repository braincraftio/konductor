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
  # ===========================================================================
  inputs = {
    # NixOS 25.11 - sync with src/lib/versions.nix nixos.channel
    # GitHub API rate limits can cause 403 errors - use FlakeHub or configure access token
    # See docs/GITHUB_AUTHENTICATION.md for token setup
    # FlakeHub URL caching causes mismatch errors - use GitHub directly
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.*";
    # nixpkgs-unstable.url = "https://flakehub.com/f/NixOS/nixpkgs/*";
    # FlakeHub URL caching causes mismatch errors - use GitHub directly
    flake-utils.url = "github:numtide/flake-utils";
    # flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/*";

    # nix2container not available on FlakeHub - requires GitHub token for updates
    nix2container = {
      # url = "github:nlewo/nix2container";
      url = "git+https://github.com/nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      # FlakeHub URL caching causes mismatch errors - use GitHub directly
      url = "github:nix-community/nixos-generators";
      # url = "https://flakehub.com/f/nix-community/nixos-generators/*";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      # FlakeHub URL caching causes mismatch errors - use GitHub directly
      url = "github:oxalica/rust-overlay";
      # url = "https://flakehub.com/f/oxalica/rust-overlay/*";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Must match nixpkgs branch - sync with src/lib/versions.nix nixos.channel
    # FIXME: ansible-language-server was removed from nixpkgs 25.11
    # Upstream issue needed in nixvim to handle this gracefully
    nixvim = {
      # url = "github:nix-community/nixvim/nixos-25.05";
      # url = "https://flakehub.com/f/nix-community/nixvim/*";
      # url = "https://flakehub.com/f/nix-community/nixvim/0.1.805";
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
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
            inherit (devshells) default python go node rust dev full konductor ci;
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
