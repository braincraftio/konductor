# src/packages/ai.nix
# AI coding assistants and tools

{
  pkgs,
  config ? null,
}:

let
  # When the wrapped Claude harness is available (config provided), ship it:
  # the wrapper seeds ~/.config/konductor-claude, loads the konductor plugins,
  # and points CLAUDE_CONFIG_DIR at the writable seed dir. Without config (base
  # devshells), fall back to the bare upstream CLI.
  claudeCode =
    if config != null && config ? claude-code then
      config.claude-code.package
    else
      pkgs.unstable.claude-code;
in
{
  packages = [
    # Claude Code ecosystem
    claudeCode # Anthropic Claude Code CLI (konductor-wrapped when config present)

    # MCP servers referenced by the konductor plugin .mcp.json.
    # These must be on PATH for the MCP config to resolve at runtime.
    pkgs.mcp-nixos # NixOS/nixpkgs/home-manager package and option search

    # Other AI assistants
    pkgs.codex # OpenAI Codex CLI
    pkgs.github-copilot-cli # GitHub Copilot CLI
  ];

  shellHook = "";
  env = { };
}
