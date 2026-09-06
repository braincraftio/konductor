# src/modules/home-manager.nix
# Home Manager module - full konductor development environment
#
# Provides the complete konductor experience in a persistent user environment:
# packages, IDE tools (neovim, tmux, ttyd), hermetic shell configuration
# (bash, starship, atuin, git), and environment variables.
#
# Usage in consumer flake.nix:
#   inputs.konductor.url = "github:braincraftio/konductor";
#
#   homeConfigurations."user" = home-manager.lib.homeManagerConfiguration {
#     modules = [
#       konductor.homeManagerModules.default
#       { konductor.enable = true; }
#     ];
#     extraSpecialArgs = { inherit (inputs) konductor; };
#   };
#
# The konductor flake input is passed via extraSpecialArgs to provide
# access to catppuccin theme sources and nixvim (same pattern as devshells + qcow2).

{
  config,
  pkgs,
  lib,
  konductor,
  ...
}:

let
  common = import ./common.nix { inherit lib; };
  cfg = config.konductor;
  versions = import ../lib/versions.nix;

  # Catppuccin theme sources from catppuccin/nix flake
  # Same pattern as src/devshells/default.nix:34 and src/qcow2/default.nix:36
  catppuccinSources = konductor.inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};

  # Config provides wrapped tools with hermetic configuration
  konductorConfig = import ../config {
    inherit
      pkgs
      lib
      versions
      catppuccinSources
      ;
  };

  # Programs (neovim, tmux, ttyd) — needs flake inputs for nixvim
  programs = import ../programs {
    inherit pkgs;
    inherit (konductor) inputs;
    inherit (konductor.inputs.nixpkgs) lib;
  };

  # Packages for IDE tools
  packages = import ../packages {
    inherit pkgs lib versions;
    config = konductorConfig;
  };
in
{
  options.konductor = common.mkOptions;

  config = lib.mkIf cfg.enable {
    home = {
      # Full devshell packages (SSOT: packages/default.nix fullPackages)
      packages =
        common.mkPackages {
          inherit
            pkgs
            lib
            versions
            catppuccinSources
            ;
        }
        # IDE programs: neovim, tmux, ttyd
        ++ common.mkPrograms { inherit programs packages; }
        # Atuin shell history (mirrors konductor.nix:47)
        ++ konductorConfig.shell.atuin.packages;

      # Config files: starship, atuin (bash/readline/inputrc via programs.bash)
      file = common.mkHomeFiles { config = konductorConfig; };

      # Full environment — mirrors konductor.nix env (lines 138-161) + shellHook exports (lines 60-110)
      sessionVariables =
        common.mkFullEnv {
          config = konductorConfig;
          sslCertFile =
            if pkgs.stdenv.hostPlatform.isDarwin then
              "/etc/ssl/cert.pem"
            else
              "/etc/ssl/certs/ca-certificates.crt";
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (packages.konductor.env pkgs)
        // konductorConfig.shell.ssh.env
        // programs.tmux.env
        # LD_LIBRARY_PATH disabled in home.sessionVariables — on non-NixOS the
        # nix glibc 2.42 libpthread poisons system binaries (glibc 2.39),
        # crashing the compositor and display manager. Devshells set this
        # via shellHook where the entire environment is nix-controlled.
        # // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        #   LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [
        #     pkgs.stdenv.cc.cc.lib
        #     pkgs.xz
        #     pkgs.zstd
        #   ]}";
        # }
        // konductorConfig.opencode.env
        // {
          # Language env vars — mirrors konductor.nix:144-153
          UV_SYSTEM_PYTHON = "1";
          PYTHONDONTWRITEBYTECODE = "1";
          GO111MODULE = "on";
          CGO_ENABLED = "1";
          NODE_ENV = "development";
          RUST_BACKTRACE = "1";
          # Shell identity
          KONDUCTOR_SHELL = "konductor";
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          # Docker — mirrors konductor.nix:101 and packages/konductor.nix:55
          DOCKER_HOST = "unix:///var/run/docker.sock";
        };

      shellAliases = common.mkAliases;
    };

    programs.bash = common.mkBashConfig;
    programs.readline = common.mkReadlineConfig;
  };
}
