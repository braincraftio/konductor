# src/packages/ai.nix
# AI coding assistants and tools

{ pkgs }:

{
  packages = with pkgs; [
    # Claude Code ecosystem
    unstable.claude-code # Anthropic Claude Code CLI
    claude-monitor # Real-time Claude Code usage monitor
    claude-code-router # Route requests to different models

    # Other AI assistants
    codex # OpenAI Codex CLI
    github-copilot-cli # GitHub Copilot CLI
  ];

  shellHook = "";
  env = { };
}
