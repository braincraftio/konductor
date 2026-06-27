# src/config/claude-code/statusline.nix
# Catppuccin Frappé powerline statusline as a hermetic derivation.
#
# Returns a writeShellApplication so:
#   - meta.mainProgram = "claude-statusline"  → lib.getExe works in default.nix
#   - runtimeInputs put jq/git/awk/coreutils on PATH hermetically (no reliance
#     on the user's environment having them)
#   - shellcheck runs at build time
#
# settings.json points statusLine.command at "${drv}/bin/claude-statusline"
# (an absolute store path), never at ~/.claude/statusline-command.sh.

{ pkgs }:

pkgs.writeShellApplication {
  name = "claude-statusline";
  runtimeInputs = with pkgs; [
    jq
    git
    gawk
    coreutils
  ];
  # The script manages its own pipefail and tolerates absent fields; the default
  # nounset/errexit would abort on the first unset optional, so relax them here.
  bashOptions = [ ];
  text = builtins.readFile ./statusline.sh;
}
