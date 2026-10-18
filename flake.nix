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
    # usrbinkat fork: gssproxy, freeipa, lesscpy, llvm patches ahead of upstream
    # Based on nixpkgs master; home-manager and nixvim track master to match
    nixpkgs.url = "github:usrbinkat/nixpkgs/gssproxy-package-and-module";
    nixpkgs-unstable.follows = "nixpkgs";

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

    # nixvim follows nixpkgs so plugin dependencies resolve from the same
    # package set as konductor. Prevents hash mismatches on vim plugins
    # whose upstream source changes between nixpkgs revisions.
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    # Tracks master to match nixpkgs fork base
    home-manager = {
      url = "github:nix-community/home-manager";
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

    # Forked Forgejo runner with workspace isolation (pre-release).
    # Single switch: declaring this input builds the fork
    # (src/programs/forgejo/runner.nix), enables konductor.forgejoRunner in
    # the qcow2 image, and exports packages.forgejo-runner. Commented out,
    # nothing references it and git.braincraft.io is never contacted.
    # Enable: uncomment, then nix flake lock.
    # forgejo-runner-src = {
    #   url = "git+https://git.braincraft.io/braincraft/runner";
    #   flake = false;
    # };

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

    # OpenCode v2 AI coding agent
    # usrbinkat fork: nix integration (bun2nix build, flake outputs, HM/NixOS/darwin modules)
    opencode = {
      url = "github:usrbinkat/opencode/v2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://braincraftio.cachix.org"
      "https://scopecreep-zip.cachix.org"
      "https://usrbinkat.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "braincraftio.cachix.org-1:VOGTfDaVaeIOMpeYYKjBhXxT5gGF2iFCKm9HA7j3WFM="
      "scopecreep-zip.cachix.org-1:LPiVDsYXJvgljVfZPN43zBWB7ZCGFr2jZ/lBinnPGvU="
      "usrbinkat.cachix.org-1:+DqaVRWbHXiXIgqBOk0+zr2rsyp+RWPe+pKm7BRROUE="
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
      inherit (nixpkgs) lib;

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
        inherit (self) narHash;
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
            overlays = [
              inputs.rust-overlay.overlays.default
              inputs.opencode.overlays.default
            ]
            ++ overlays;
            config = {
              allowUnfree = true;
            };
          };
          versions = import ./src/lib/versions.nix;

          # Website data derivation: versions.nix as JSON, cached and
          # content-addressed. Replaces nix eval --json shell commands
          # in CI and mise tasks with a single nix build .#versions-json.
          versionsJson = pkgs.writeText "versions.json" (builtins.toJSON versions);

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

          # CI runner toolchain: nix profile install .#ci
          # Consumed by .github/actions/setup-devshell. Node is the versions.nix pin.
          ciEnv = pkgs.buildEnv {
            name = "konductor-ci";
            paths = [
              pkgs.konductor.nodejs
              pkgs.pnpm
              pkgs.git
              pkgs.jq
              pkgs.cachix
              pkgs.actionlint
              pkgs.gh
              pkgs.unstable.runme
              pkgs.nix-update
            ];
            meta.description = "Konductor CI runner toolchain";
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

          # Source quality gates: the same wrapped tools lefthook and runme
          # invoke. The flake source is git-tracked content only, so gitignored
          # trees (_sources/) are absent by construction. Filesets narrow each
          # check's input hash to the files it reads.
          nixSources = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
          };
          lintChecks = {
            # treefmt --ci formats in place and fails on change, so it runs on a
            # writable copy. The sandbox has no .git: walk the filesystem. The
            # root is resolved by the config's tree-root-file (flake.nix) from
            # --working-dir; passing --tree-root as well is rejected by treefmt.
            treefmt = pkgs.runCommand "check-treefmt" { } ''
              cp -r --no-preserve=mode ${./.} source
              export HOME="$TMPDIR"
              ${lib.getExe konductorConfig.formatters.treefmt.package} \
                --ci --walk filesystem --working-dir source
              touch $out
            '';
            statix =
              pkgs.runCommand "check-statix" { nativeBuildInputs = [ konductorConfig.linters.statix.package ]; }
                ''
                  statix check ${nixSources}
                  touch $out
                '';
            deadnix =
              pkgs.runCommand "check-deadnix" { nativeBuildInputs = [ konductorConfig.linters.deadnix.package ]; }
                ''
                  deadnix --fail -- ${nixSources}
                  touch $out
                '';
          };
        in
        {
          inherit
            pkgs
            versions
            versionsJson
            packages
            programs
            devshells
            qcow2
            oci
            konductorConfig
            konductorEnv
            ciEnv
            toolChecks
            bundleCheck
            lintChecks
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
          ci = sb.ciEnv;
          # Website data: nix build .#versions-json
          # Replaces nix eval --json shell commands in CI and mise tasks.
          versions-json = sb.versionsJson;

          # Maintenance targets reuse the exact devshell package set. Dependency
          # hashes can be refreshed with .#atuin.cargoDeps / .#k0sctl.goModules.
          inherit (sb.pkgs)
            atuin
            flakehub-push
            k0sctl
            terminal-browser
            opencode
            ;
          mitogen = sb.packages.ansible.mitogen;
          ansible = sb.packages.ansible.package;
          python-env = sb.packages.pythonEnv;
          pulumi = sb.packages.languages.pulumiPkg.package;
          pulumi-cli = sb.packages.languages.pulumiPkg.cli;
          trzsz = sb.pkgs.callPackage ./src/packages/trzsz.nix { };
          prettier-plugin-astro = sb.konductorConfig.formatters.prettier.astroPlugin;
          treefmt = sb.konductorConfig.formatters.treefmt.package;
        }
        # Present only when the forgejo-runner-src input is declared.
        // lib.optionalAttrs (sb.programs.forgejo.runner != null) {
          forgejo-runner = sb.programs.forgejo.runner;
        }
        // lib.optionalAttrs sb.pkgs.stdenv.hostPlatform.isLinux {
          oci = sb.oci.image;
          k0s = sb.pkgs.konductor.k0s;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          qcow2 = sb.qcow2.image;
          code-server = sb.pkgs.code-server;
        }
      );

      # Functional checks: nix flake check
      # Per-tool checks depend only on their own closure (per-tool cache invalidation).
      # Bundle check verifies buildEnv composition (catches collisions).
      # Lint checks gate formatting (treefmt), Nix lints (statix), and dead
      # code (deadnix).
      checks = forAllSystems (
        _system: sb: sb.toolChecks // sb.lintChecks // { inherit (sb) bundleCheck; }
      );

      # nix fmt [paths] / nix fmt -- --ci: treefmt bound to every konductor
      # formatter, the same binary checks.treefmt and lefthook run.
      formatter = forAllSystems (_system: sb: sb.konductorConfig.formatters.treefmt.package);

      apps = forAllSystems (
        _system: sb: {
          update-artifacts =
            let
              app = import ./src/apps/update-artifacts.nix { inherit (sb) pkgs versions; };
            in
            {
              type = "app";
              program = lib.getExe app;
              meta.description = app.meta.description;
            };
          update-prettier-astro-lock =
            let
              app = import ./src/apps/update-prettier-astro-lock.nix { inherit (sb) pkgs versions; };
            in
            {
              type = "app";
              program = lib.getExe app;
              meta.description = app.meta.description;
            };
        }
      );
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
        # Forgejo Actions runner daemon (konductor.forgejoRunner.*); disabled
        # by default, consumer supplies konductor.forgejoRunner.package.
        forgejo-runner = import ./src/modules/forgejo-runner.nix;
      };

      # Home Manager module. `homeModules` is the output name `nix flake check`
      # recognizes (Nix 2.34 known-output list), so it is type-checked as a
      # module set instead of warning "unknown flake output".
      homeModules = {
        konductor = import ./src/modules/home-manager.nix;
        default = import ./src/modules/home-manager.nix;
      };

      # nix-darwin module; `darwinModules` is a known flake output name.
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
