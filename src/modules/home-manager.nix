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

{ config, pkgs, lib, konductor, ... }:

let
  common = import ./common.nix { inherit lib; };
  cfg = config.konductor;
  versions = import ../lib/versions.nix;

  # Catppuccin theme sources from catppuccin/nix flake
  # Same pattern as src/devshells/default.nix:34 and src/qcow2/default.nix:36
  catppuccinSources = konductor.inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};

  # Config provides wrapped tools with hermetic configuration
  konductorConfig = import ../config { inherit pkgs lib versions catppuccinSources; };

  # Programs (neovim, tmux, ttyd) — needs flake inputs for nixvim
  programs = import ../programs {
    inherit pkgs;
    inherit (konductor) inputs;
    inherit (konductor.inputs.nixpkgs) lib;
  };

  # Packages for IDE tools
  packages = import ../packages { inherit pkgs lib versions; config = konductorConfig; };
in
{
  options.konductor = common.mkOptions;

  config = lib.mkIf cfg.enable {
    home = {
      # Base + language packages
      packages = common.mkPackages {
        inherit cfg pkgs lib versions catppuccinSources;
      }
      # IDE programs: neovim, tmux, ttyd
      ++ common.mkPrograms { inherit programs packages; };

      # Config files: bashrc, starship, atuin, inputrc, bash_profile
      file = common.mkHomeFiles { config = konductorConfig; };

      # Full environment: base (EDITOR, PAGER) + tool paths (ATUIN_CONFIG_DIR, BASH_ENV, etc.)
      # + konductor self-hosting env (OVMF_CODE, OVMF_VARS, DOCKER_BUILDKIT)
      # + LD_LIBRARY_PATH for native extensions (grpcio, etc.) — mirrors konductor.nix:61-65
      sessionVariables = common.mkFullEnv { config = konductorConfig; }
        // (packages.konductor.env pkgs)
        // {
          LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib";
        };

      shellAliases = common.mkAliases;
    };
  };
}
