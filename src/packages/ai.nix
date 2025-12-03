# src/packages/ai.nix
# AI coding assistants and tools

{ pkgs }:

{
  packages = with pkgs; [
    unstable.claude-code # Anthropic Claude Code CLI
    codex # OpenAI Codex CLI
    github-copilot-cli # GitHub Copilot CLI
  ];

  shellHook = "";
  env = { };
}
