# src/config/shell/git.nix
# Git configuration
# Uses centralized shell-content from SSOT

{ pkgs, lib }:

let
  # Import centralized shell content
  shellContent = import ../../lib/shell-content.nix { inherit lib; };

  configFile = pkgs.writeText "konductor-gitconfig" shellContent.gitconfigContent;

in
{
  # Git package
  package = pkgs.git;
  unwrapped = pkgs.git;

  # Config file
  inherit configFile;
  configContent = shellContent.gitconfigContent;

  # Metadata
  meta = {
    description = "Git with Konductor configuration";
    configurable = true;
  };
}
