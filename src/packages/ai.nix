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

    # Other AI assistants
    pkgs.codex # OpenAI Codex CLI
    pkgs.github-copilot-cli # GitHub Copilot CLI
  ];

  shellHook = "";
  env = { };
}
