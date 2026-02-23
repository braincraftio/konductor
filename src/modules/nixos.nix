# src/modules/nixos.nix
# NixOS module implementation
#
# Usage in consumer flake.nix:
#   modules = [
#     konductor.nixosModules.default
#     { konductor.enable = true; }
#   ];
#   specialArgs = { inherit (inputs) konductor; };
#
# The konductor flake input is passed via specialArgs to provide
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
    environment.systemPackages = common.mkPackages {
      inherit cfg pkgs lib versions catppuccinSources;
    };
    environment.variables = common.mkEnv;
  };
}
