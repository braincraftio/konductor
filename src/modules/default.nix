# src/modules/default.nix
# Module aggregation for NixOS, Home Manager, and nix-darwin

{
  nixos = import ./nixos.nix;
  homeManager = import ./home-manager.nix;
  darwin = import ./darwin.nix;
}
