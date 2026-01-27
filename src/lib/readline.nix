# k9/src/lib/readline.nix
# SSOT for readline/inputrc configuration
# Used by: src/programs/tmux/default.nix, src/config/shell/bash.nix
#
# This eliminates duplicate inputrc definitions across the codebase.
# All consumers import this module to ensure consistent readline behavior.

{ pkgs }:

let
  # Canonical inputrc content - single source of truth
  inputrcContent = ''
    # Konductor Readline Configuration
    # Terminal key handling
    set enable-keypad on
    set input-meta on
    set output-meta on
    set convert-meta off

    # Arrow key navigation
    "\e[A": previous-history
    "\e[B": next-history
    "\e[C": forward-char
    "\e[D": backward-char

    # Home/End/Delete
    "\e[H": beginning-of-line
    "\e[F": end-of-line
    "\e[3~": delete-char

    # Completion behavior
    set completion-ignore-case on
    set show-all-if-ambiguous on
    set colored-stats on
    set visible-stats on
    set mark-symlinked-directories on
  '';

  # Derivation for file-based usage
  inputrcFile = pkgs.writeText "konductor-inputrc" inputrcContent;

in {
  # Raw content for inline usage (shell-content.nix, etc.)
  content = inputrcContent;

  # File derivation for path references
  file = inputrcFile;

  # Path as string
  path = "${inputrcFile}";
}
