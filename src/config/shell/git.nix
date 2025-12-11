# src/config/shell/git.nix
# Git configuration wrapper
#
# Config is generated from centralized shell-content.nix SSOT.
# The wrapper forces config via GIT_CONFIG_GLOBAL env var with no escape hatch.

{ pkgs, lib }:

let
  # Import centralized shell content
  shellContent = import ../../lib/shell-content.nix { inherit lib; };

  # Config file - written to nix store
  configFile = pkgs.writeTextFile {
    name = "konductor-gitconfig";
    destination = "/.gitconfig";
    text = shellContent.gitconfigContent;
  };

in
{
  # Wrapped git that forces hermetic config
  package = pkgs.writeShellApplication {
    name = "git";
    runtimeInputs = [ pkgs.git ];
    text = ''
      export GIT_CONFIG_GLOBAL="${configFile}/.gitconfig"
      exec git "$@"
    '';
  };

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
