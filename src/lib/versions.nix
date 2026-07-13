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
    channel = "26.05";
    stateVersion = "26.05";
  };

  languages = {
    python = {
      version = "313";
      display = "3.13";
    };
    go = {
      version = "1_25";
      display = "1.25";
    };
    node = {
      version = "22";
      display = "22";
    };
    rust = {
      version = "1.92.0";
      display = "1.92.0";
    };
  };

  ansible = {
    mitogen = "0.3.50";
    serverscomCollection = "1.4.1";
  };

  # Kubernetes distribution tooling — tip-of-spear policy.
  # k0s.attr selects the package from the k0s-nix overlay (k0s_1_27..k0s_1_35);
  # the embedded Kubernetes version is coupled to k0s upstream (1.35.x ↔ k8s
  # 1.35.x) and is not managed here. k0sctl is pinned via src/overlays/k0s.nix
  # because nixpkgs channels lag upstream releases; bumping k0sctl = update
  # version here + src/vendor hashes in that overlay.
  kubernetes = {
    k0s = {
      attr = "k0s_1_35";
      display = "1.35";
    };
    k0sctl = {
      version = "0.31.1";
      display = "0.31.1";
    };
  };

  image = {
    name = "ghcr.io/braincraftio/konductor";
  };

  # Shell history — tip-of-spear policy to prevent SQLite migration skew
  # between konductor devshells and home-manager consumers on different
  # nixpkgs channels. Pinned via src/overlays/atuin.nix; bumping = update
  # version here + src/vendor hashes in that overlay.
  atuin = {
    version = "18.16.1";
    display = "18.16.1";
  };

  nix = {
    minimum = "2.24.0";
    recommended = "2.24.10";
  };
}
