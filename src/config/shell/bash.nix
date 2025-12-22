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

  # Inputrc for readline configuration
  inputrcFile = pkgs.writeTextFile {
    name = "konductor-inputrc";
    destination = "/.inputrc";
    text = ''
      set enable-keypad on
      set input-meta on
      set output-meta on
      set convert-meta off
      "\e[A": previous-history
      "\e[B": next-history
      "\e[C": forward-char
      "\e[D": backward-char
      "\e[H": beginning-of-line
      "\e[F": end-of-line
      "\e[3~": delete-char
      set completion-ignore-case on
      set show-all-if-ambiguous on
      set colored-stats on
    '';
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

  meta = {
    description = "Bash shell with Konductor configuration";
    configurable = true;
  };
}
