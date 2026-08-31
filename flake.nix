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
    # NixOS 26.05 - sync with src/lib/versions.nix nixos.channel
    # gssproxy: fork until PR merges, then switch to upstream
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs.url = "github:usrbinkat/nixpkgs/gssproxy-package-and-module";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # flake-utils and systems are retained for nuschtosSearch, ixx, and
    # nixvim follows declarations. Per-system iteration uses
    # lib.genAttrs supportedSystems directly.
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

    # nixvim uses its own pinned nixpkgs for building; no
    # nixpkgs.follows to avoid nixos-render-docs rebuild conflicts
    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs = {
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
      };
    };

    # Must match nixpkgs branch - sync with src/lib/versions.nix nixos.channel
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Catppuccin themes for k9s and other applications
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Open Sesame: headless encrypted secret vaults with SSH agent unlock
    # No follows — derivation hashes must match scopecreep-zip.cachix.org
    open-sesame = {
      url = "github:ScopeCreep-zip/open-sesame";
    };

    # Forked Forgejo runner with workspace isolation
    # TODO: switch back to git.docker.arpa/containercraft/runner
    #        once nix daemon git auth for Gitea is resolved (netrc-file or equivalent)
    # Update: nix flake update forgejo-runner-src
    forgejo-runner-src = {
      url = "git+https://git.braincraft.io/braincraft/runner";
      flake = false;
    };

    # k0s Kubernetes distribution: binary packages (k0s_1_27..k0s_1_35) +
    # services.k0s NixOS module. Tracks main (maintainers treat main as
    # stable; CI-tested per commit). MIT-licensed for nixpkgs
    # upstreamability — issues we hit get contributed upstream rather
    # than forked around.
    # Update: nix flake update k0s-nix
    k0s-nix = {
      url = "github:nix-community/k0s-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://braincraftio.cachix.org"
      "https://scopecreep-zip.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "braincraftio.cachix.org-1:VOGTfDaVaeIOMpeYYKjBhXxT5gGF2iFCKm9HA7j3WFM="
      "scopecreep-zip.cachix.org-1:LPiVDsYXJvgljVfZPN43zBWB7ZCGFr2jZ/lBinnPGvU="
    ];
    download-buffer-size = 268435456; # 256MB — suppress "download buffer is full" warnings
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;

      # Import overlays
      overlays = import ./src/overlays {
        inherit lib;
        inherit (inputs) nixpkgs-unstable k0s-nix;
      };

      # Flake source metadata — available at eval time, not runtime
      sourceInfo = {
        rev = self.rev or null;
        shortRev = self.shortRev or "dirty";
        lastModifiedDate = self.lastModifiedDate or "19700101000000";
        narHash = self.narHash;
      };

      # Single system list — one source of truth for all per-system outputs.
      # flake-utils and systems inputs are retained only for downstream
      # follows (nuschtosSearch, ixx, nixvim). Iteration uses lib.genAttrs.
      # x86_64-darwin removed: nixpkgs-unstable (26.11) dropped x86_64-darwin.
      # The unstable overlay imports nixpkgs-unstable at eval time, which
      # throws on x86_64-darwin regardless of whether unstable packages are
      # used. nixos-26.05 still supports x86_64-darwin through end of 2026
      # but the unstable import makes it unreachable. Re-evaluate when
      # nixpkgs-unstable re-adds x86_64-darwin or the unstable overlay
      # gains a platform guard.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Per-system bindings computed once via genAttrs, indexed everywhere.
      # Both forAllSystems and nixosConfigurations read from this table,
      # sharing thunks instead of re-evaluating pkgs/overlays/src imports.
      systemBindings = lib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ inputs.rust-overlay.overlays.default ] ++ overlays;
            config = {
              allowUnfree = true;
              permittedInsecurePackages = [
                "nodejs-20.20.2"
                "nodejs-slim-20.20.2"
              ];
            };
          };
          versions = import ./src/lib/versions.nix;
          catppuccinSources = inputs.catppuccin.packages.${system};
          konductorConfig = import ./src/config {
            inherit
              pkgs
              versions
              catppuccinSources
              lib
              ;
          };
          packages = import ./src/packages {
            inherit pkgs versions lib;
            config = konductorConfig;
          };
          programs = import ./src/programs {
            inherit pkgs inputs lib;
          };
          devshells = import ./src/devshells {
            inherit
              pkgs
              inputs
              versions
              programs
              sourceInfo
              lib
              ;
          };
          qcow2 = import ./src/qcow2 {
            inherit
              pkgs
              nixpkgs
              inputs
              system
              versions
              programs
              devshells
              lib
              ;
          };
          oci = import ./src/oci {
            inherit pkgs inputs lib;
            inherit (inputs.nix2container.packages.${system}) nix2container;
          };

          # Installable package: nix profile install github:braincraftio/konductor
          # Same composition as the full devshell: fullPackages + neovim + tmux + atuin
          konductorEnv = pkgs.buildEnv {
            name = "konductor-env";
            paths =
              packages.fullPackages
              ++ programs.neovim.packages
              ++ programs.tmux.packages
              ++ konductorConfig.shell.atuin.packages;
            meta.description = "Konductor polyglot development environment";
          };

          # Per-tool version checks: each depends only on its own package
          # closure, so bumping one tool does not invalidate other checks.
          # Follows nixpkgs testers.testVersion pattern.
          toolChecks = {
            nvim =
              pkgs.runCommand "check-nvim"
                {
                  nativeBuildInputs = programs.neovim.packages;
                  meta.timeout = 60;
                }
                ''
                  nvim --version > /dev/null && touch $out
                '';
            tmux =
              pkgs.runCommand "check-tmux"
                {
                  nativeBuildInputs = programs.tmux.packages;
                  meta.timeout = 60;
                }
                ''
                  tmux -V > /dev/null && touch $out
                '';
            git =
              pkgs.runCommand "check-git"
                {
                  nativeBuildInputs = [ pkgs.git ];
                  meta.timeout = 60;
                }
                ''
                  git --version > /dev/null && touch $out
                '';
            jq =
              pkgs.runCommand "check-jq"
                {
                  nativeBuildInputs = [ pkgs.jq ];
                  meta.timeout = 60;
                }
                ''
                  jq --version > /dev/null && touch $out
                '';
            rg =
              pkgs.runCommand "check-rg"
                {
                  nativeBuildInputs = [ pkgs.ripgrep ];
                  meta.timeout = 60;
                }
                ''
                  rg --version > /dev/null && touch $out
                '';
            atuin =
              pkgs.runCommand "check-atuin"
                {
                  nativeBuildInputs = [ pkgs.atuin ];
                  meta.timeout = 60;
                }
                ''
                  atuin --version > /dev/null && touch $out
                '';
            starship =
              pkgs.runCommand "check-starship"
                {
                  nativeBuildInputs = [ pkgs.starship ];
                  meta.timeout = 60;
                }
                ''
                  starship --version > /dev/null && touch $out
                '';
            kubectl =
              pkgs.runCommand "check-kubectl"
                {
                  nativeBuildInputs = [ pkgs.unstable.kubectl ];
                  meta.timeout = 60;
                }
                ''
                  kubectl version --client > /dev/null && touch $out
                '';
          };

          # Bundle integration: verifies buildEnv composition succeeds without
          # collisions and the resulting env is a valid store path. This rebuilds
          # on any constituent change but catches collision regressions that
          # per-tool checks cannot detect.
          bundleCheck =
            pkgs.runCommand "check-bundle"
              {
                nativeBuildInputs = [ konductorEnv ];
                meta.timeout = 120;
              }
              ''
                test -d ${konductorEnv}/bin && touch $out
              '';
        in
        {
          inherit
            pkgs
            versions
            packages
            programs
            devshells
            qcow2
            oci
            konductorConfig
            konductorEnv
            toolChecks
            bundleCheck
            ;
        }
      );

      # Per-system output builder using the shared systemBindings table
      forAllSystems = f: lib.genAttrs supportedSystems (system: f system systemBindings.${system});

    in

    # Per-system outputs (devShells, packages, checks)
    {
      devShells = forAllSystems (
        system: sb:
        {
          inherit (sb.devshells)
            default
            python
            go
            node
            rust
            dev
            full
            ;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          inherit (sb.devshells) konductor frontend;
        }
      );

      packages = forAllSystems (
        system: sb:
        {
          default = sb.konductorEnv;
        }
        // lib.optionalAttrs sb.pkgs.stdenv.hostPlatform.isLinux {
          oci = sb.oci.image;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          qcow2 = sb.qcow2.image;
        }
      );

      # Functional checks: nix flake check
      # Per-tool checks depend only on their own closure (per-tool cache invalidation).
      # Bundle check verifies buildEnv composition (catches collisions).
      checks = forAllSystems (_system: sb: sb.toolChecks // { inherit (sb) bundleCheck; });
    }

    # Cross-system outputs (modules, overlays, nixosConfigurations)
    // {
      overlays.default = lib.composeManyExtensions overlays;

      # NixOS configurations for live rebuilds on running VMs
      # Usage: sudo nixos-rebuild switch --flake .#konductor
      nixosConfigurations.konductor =
        let
          inherit (systemBindings."x86_64-linux") qcow2;
        in
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ qcow2.konductorModule ];
        };

      # NixOS module - standard flake output per `nix flake check --help`
      nixosModules = {
        konductor = import ./src/modules/nixos.nix;
        default = import ./src/modules/nixos.nix;
        # k0s Kubernetes distribution (services.k0s.*) — re-exported from
        # k0s-nix so konductor consumers get the module from one flake.
        # Disabled by default (mkEnableOption); on-demand capability.
        k0s = inputs.k0s-nix.nixosModules.default;
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

      # Project scaffolding: nix flake init -t github:braincraftio/konductor
      templates = {
        konductor = {
          path = ./templates/konductor;
          description = "Konductor standalone project with full devshell";
          welcomeText = ''
            # Konductor Project

            Run `direnv allow` to activate the development environment.

            First run will prompt to trust the cachix substituters.
            Accept to enable binary cache downloads.
          '';
        };
        workspace = {
          path = ./templates/workspace;
          description = "Konductor multi-repo workspace with child inheritance";
          welcomeText = ''
            # Konductor Workspace

            Run `direnv allow` to activate the development environment.

            Clone repos into this directory. Each repo with its own .envrc
            inherits WORKSPACE_ROOT, vault injection, and nix auth from
            this workspace via source_up_if_exists.
          '';
        };
        default = self.templates.konductor;
      };
    };
}
