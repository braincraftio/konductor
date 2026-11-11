{ pkgs }:
{
  scope = "project";
  # Preserve the upstream skill directory and its relative resource paths.
  directory = "${pkgs.terminal-browser}/lib/terminal-browser/skills/default/terminal-browser";
}
