# src/lib/versions.nix
# Single Source of Truth for all version-locked values
# NO pkgs dependency - pure data only

{
  # ===========================================================================
  # Language Runtimes
  # ===========================================================================
  languages = {
    python = {
      version = "312"; # Maps to pkgs.python312
      display = "3.12"; # Human-readable
    };
    go = {
      version = "1_24"; # Maps to pkgs.go_1_24
      display = "1.24";
    };
    node = {
      version = "22"; # Maps to pkgs.nodejs_22
      display = "22";
    };
    rust = {
      version = "1.82.0"; # Maps to rust-bin.stable."1.82.0"
      display = "1.82.0";
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
