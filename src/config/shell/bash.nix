# src/config/shell/bash.nix
# Hermetic wrapper for bash shell configuration
#
# Config is maintained in native format (.bashrc) for easy contribution.
# This follows the same pattern as markdownlint-cli2 wrapper.

{ pkgs, ... }:

let
  # Config file - native bashrc, copied directly to nix store
  bashrcFile = pkgs.writeTextFile {
    name = "konductor-bashrc";
    destination = "/.bashrc";
    text = builtins.readFile ./.bashrc;
  };

  # Import shared readline configuration (SSOT - eliminates duplicate definitions)
  readline = import ../../lib/readline.nix { inherit pkgs; };

  # Inputrc with destination path for this module's usage pattern
  inputrcFile = pkgs.writeTextFile {
    name = "konductor-inputrc";
    destination = "/.inputrc";
    text = readline.content;
  };

in
{
  # Wrapped bash that sources our hermetic bashrc
  package = pkgs.writeShellApplication {
    name = "bash";
    runtimeInputs = [ pkgs.bashInteractive ];
    text = ''
      export INPUTRC="${inputrcFile}/.inputrc"
      exec bash --rcfile "${bashrcFile}/.bashrc" "$@"
    '';
  };

  unwrapped = pkgs.bashInteractive;

  # Export config files for other uses (devshells, containers)
  configFiles = {
    bashrc = bashrcFile;
    inputrc = inputrcFile;
  };

  # Raw content for injection into shellHooks
  bashrcContent = builtins.readFile ./.bashrc;

  # Environment variables for runme/automation
  # BASH_ENV: bash sources this for non-interactive shells (runme uses bash -c)
  # KONDUCTOR_BASHRC: explicit path for scripts that need to source manually
  env = {
    BASH_ENV = "${bashrcFile}/.bashrc";
    KONDUCTOR_BASHRC = "${bashrcFile}/.bashrc";
    KONDUCTOR_INPUTRC = "${inputrcFile}/.inputrc";
  };

  meta = {
    description = "Bash shell with Konductor configuration";
    configurable = true;
  };
}
