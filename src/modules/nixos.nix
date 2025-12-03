# src/modules/nixos.nix
# NixOS module implementation

{ config, pkgs, lib, ... }:

let
  common = import ./common.nix { inherit lib; };
  cfg = config.konductor;
  versions = import ../lib/versions.nix;
in
{
  options.konductor = common.mkOptions;

  config = lib.mkIf cfg.enable {
    environment.systemPackages = common.mkPackages {
      inherit cfg pkgs lib versions;
    };
    environment.variables = common.mkEnv;
  };
}
