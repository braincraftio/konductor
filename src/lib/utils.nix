# src/lib/utils.nix
# Pure helper functions (no pkgs dependency)

{ lib }:

{
  # ===========================================================================
  # Version String Helpers
  # ===========================================================================

  # Convert "3.13" -> "313" for package names
  versionToPackage = version: lib.replaceStrings [ "." ] [ "" ] version;

  # Convert "1.24" -> "1_24" for Go package names
  versionToGo = version: lib.replaceStrings [ "." ] [ "_" ] version;

  # ===========================================================================
  # Path Helpers
  # ===========================================================================

  # Safely join paths
  joinPaths = paths: lib.concatStringsSep "/" (lib.filter (p: p != "") paths);

  # ===========================================================================
  # List Helpers
  # ===========================================================================

  # Merge package lists with deduplication
  mergePackages = packageLists: lib.unique (lib.flatten packageLists);

  # ===========================================================================
  # String Helpers
  # ===========================================================================

  # Create section separator for comments
  mkSectionSeparator = title: ''
    # ═══════════════════════════════════════════════════════════════════════════
    # ${title}
    # ═══════════════════════════════════════════════════════════════════════════
  '';
}
