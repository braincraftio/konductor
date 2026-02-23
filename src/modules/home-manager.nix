# src/modules/home-manager.nix
# Home Manager module
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
# access to catppuccin theme sources (same pattern as devshells + qcow2).

{ config, pkgs, lib, konductor, ... }:

let
  common = import ./common.nix { inherit lib; };
  cfg = config.konductor;
  versions = import ../lib/versions.nix;

  # Catppuccin theme sources from catppuccin/nix flake
  # Same pattern as src/devshells/default.nix:34 and src/qcow2/default.nix:36
  catppuccinSources = konductor.inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.konductor = common.mkOptions;

  config = lib.mkIf cfg.enable {
    home = {
      packages = common.mkPackages {
        inherit cfg pkgs lib versions catppuccinSources;
      };
      sessionVariables = common.mkEnv;
      shellAliases = common.mkAliases;
    };
  };
}
