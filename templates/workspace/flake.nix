{
  description = "Workspace using Konductor development environment";

  inputs = {
    konductor.url = "github:braincraftio/konductor";
    nixpkgs.follows = "konductor/nixpkgs";
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://scopecreep-zip.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "scopecreep-zip.cachix.org-1:LPiVDsYXJvgljVfZPN43zBWB7ZCGFr2jZ/lBinnPGvU="
    ];
  };

  outputs =
    { konductor, nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems f;
    in
    {
      devShells = forAllSystems (system: {
        default = konductor.devShells.${system}.full;
      });
    };
}
