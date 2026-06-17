# src/lib/versions.nix
# Single Source of Truth for all version-locked values
#
# This file has no pkgs dependency. Pure data.
# Every devshell, container, VM, and module inherits from here.
#
# When changing nixos.channel, also update:
#   - flake.nix: nixpkgs.url and nixvim.url branches
#   - home-manager.url branch (must match nixpkgs)

{
  nixos = {
    channel = "25.11";
    stateVersion = "25.11";
  };

  languages = {
    python = { version = "313";   display = "3.13";   };
    go     = { version = "1_25";  display = "1.25";   };
    node   = { version = "22";    display = "22";     };
    rust   = { version = "1.92.0"; display = "1.92.0"; };
  };

  image = {
    name = "ghcr.io/braincraftio/konductor";
  };

  nix = {
    minimum = "2.24.0";
    recommended = "2.24.10";
  };
}
