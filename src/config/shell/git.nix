# src/config/shell/git.nix
# Git configuration wrapper
#
# Config is generated from centralized shell-content.nix SSOT.
# Uses GIT_CONFIG_SYSTEM for defaults, allowing user overrides in ~/.gitconfig.
#
# Git config precedence (highest to lowest):
#   1. Repository config (.git/config)
#   2. Global config (~/.gitconfig) - user can write/override here
#   3. System config (GIT_CONFIG_SYSTEM) - our Konductor defaults

{ pkgs, lib }:

let
  # Import centralized shell content
  shellContent = import ../../lib/shell-content.nix { inherit lib; };

  # Config file - written to nix store (read-only defaults)
  configFile = pkgs.writeTextFile {
    name = "konductor-gitconfig";
    destination = "/.gitconfig";
    text = shellContent.gitconfigContent;
  };

in
{
  # Wrapped git with Konductor defaults as system config
  # User's ~/.gitconfig can override any setting
  package = pkgs.writeShellApplication {
    name = "git";
    runtimeInputs = [ pkgs.git ];
    text = ''
      export GIT_CONFIG_SYSTEM="${configFile}/.gitconfig"
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
