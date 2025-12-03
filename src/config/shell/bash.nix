# src/config/shell/bash.nix
# Bash shell configuration with hermetic config files
# Uses centralized shell-content from SSOT

{ pkgs, lib, ... }:

let
  # Import centralized shell content
  shellContent = import ../../lib/shell-content.nix { inherit lib; };

  # Write configuration files - use devshell version (env set by mkShell)
  bashrc = pkgs.writeText "konductor-bashrc" shellContent.bashrcContentDevshell;
  bashProfile = pkgs.writeText "konductor-bash_profile" shellContent.bashProfileContent;
  inputrc = pkgs.writeText "konductor-inputrc" shellContent.inputrcContent;

in
{
  # Wrapped bash package (not typically wrapped, but config provided)
  package = pkgs.bashInteractive;
  unwrapped = pkgs.bashInteractive;

  # Config files
  configFiles = {
    inherit bashrc bashProfile inputrc;
  };

  # Content for embedding in other configs
  inherit (shellContent) bashrcContentDevshell bashrcContentStandalone bashProfileContent inputrcContent;

  # Metadata
  meta = {
    description = "Bash shell with Konductor configuration";
    configurable = true;
  };
}
