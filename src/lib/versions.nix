# src/lib/versions.nix
# Single Source of Truth for all version-locked values
# NO pkgs dependency - pure data only

{
  # ===========================================================================
  # NixOS/Nixpkgs Release Channel
  # ===========================================================================
  # IMPORTANT: This is the canonical version reference.
  # When changing, also update these locations (flake inputs cannot import nix files):
  #   - flake.nix: nixpkgs.url and nixvim.url branches
  #   - src/qcow2/default.nix: system.stateVersion
  nixos = {
    channel = "25.11"; # NixOS release channel (e.g., "25.11", "24.11")
    stateVersion = "25.11"; # NixOS stateVersion for VMs
  };

  # ===========================================================================
  # Language Runtimes
  # ===========================================================================
  # TODO: Review language versions periodically for LTS/stable updates
  languages = {
    python = {
      version = "313"; # Maps to pkgs.python313
      display = "3.13"; # Human-readable
    };
    go = {
      version = "1_24"; # Maps to pkgs.go_1_24 (1.23 is EOL)
      display = "1.24";
    };
    node = {
      version = "22"; # Maps to pkgs.nodejs_22
      display = "22";
    };
    rust = {
      version = "1.92.0"; # Maps to rust-bin.stable."1.92.0"
      display = "1.92.0";
    };
  };

  # ===========================================================================
  # Container/VM Metadata
  # ===========================================================================
  image = {
    name = "ghcr.io/braincraftio/konductor";
    created = "2025-01-15T00:00:00Z";
    epoch = "1736899200";
  };

  # ===========================================================================
  # Nix Version Requirements
  # ===========================================================================
  nix = {
    minimum = "2.24.0";
    recommended = "2.24.10";
  };
}
