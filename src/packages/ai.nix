# src/packages/ai.nix
# AI coding assistants and tools

{ pkgs }:

{
  packages = with pkgs; [
    # Claude Code ecosystem
    unstable.claude-code # Anthropic Claude Code CLI
    # unstable.claude-code-acp # ACP-compatible agent — removed from nixpkgs-unstable
    unstable.vscode-extensions.anthropic.claude-code # Official VS Code extension

    # Other AI assistants
    codex # OpenAI Codex CLI
    github-copilot-cli # GitHub Copilot CLI
  ];

  shellHook = "";
  env = { };
}
