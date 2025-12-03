# src/modules/home-manager.nix
# Home Manager module
#
# Usage:
#   imports = [ inputs.konductor.homeModules.default ];
#   konductor.enable = true;

{ config, pkgs, lib, ... }:

let
  common = import ./common.nix { inherit lib; };
  cfg = config.konductor;
  versions = import ../lib/versions.nix;
in
{
  options.konductor = common.mkOptions;

  config = lib.mkIf cfg.enable {
    home = {
      packages = common.mkPackages {
        inherit cfg pkgs lib versions;
      };
      sessionVariables = common.mkEnv;
      shellAliases = common.mkAliases;
    };
  };
}
