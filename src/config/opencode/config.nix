# src/config/opencode/config.nix
# opencode.json content — hermetic MCP servers, permissions, formatters, LSP.
#
# Every external binary path uses lib.getExe for store-path hermicity.
# Consumed by default.nix via pkgs.formats.json.

{ pkgs, lib }:

{
  "$schema" = "https://opencode.ai/config.json";

  # Free model from OpenCode Zen for title generation (no API key required)
  small_model = "opencode/gpt-5-nano";

  # Nix-managed — disable auto-update (binary comes from nixpkgs)
  autoupdate = false;

  # =========================================================================
  # Commands — slash commands injected via OPENCODE_CONFIG_CONTENT
  # =========================================================================
  command = {
    commit = {
      description = "Stage and commit changes using conventional commits ceremony";
      template = "Load the git-commit skill and execute all steps of the commit ceremony. NEVER truncate output: no | head, no | tail, no > file, no --stat alone, no --oneline. $ARGUMENTS";
    };
  };

  # =========================================================================
  # MCP servers — hermetic store-path commands
  # =========================================================================
  mcp = {
    deepwiki = {
      type = "remote";
      url = "https://mcp.deepwiki.com/mcp";
    };
    nixos = {
      type = "local";
      command = [ (lib.getExe pkgs.mcp-nixos) ];
    };
    github = {
      type = "local";
      command = [
        (lib.getExe pkgs.github-mcp-server)
        "stdio"
      ];
      environment = {
        GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_PERSONAL_ACCESS_TOKEN}";
      };
    };
    gitea = {
      type = "local";
      command = [
        (lib.getExe pkgs.gitea-mcp-server)
        "-host"
        "{env:GITEA_URL}"
        "-token"
        "{env:GITEA_TOKEN}"
      ];
    };
    kubernetes = {
      type = "local";
      command = [ (lib.getExe pkgs.mcp-k8s-go) ];
    };
  };

  # =========================================================================
  # Permissions — v1 object keyed by tool name, last matching rule wins.
  # Bare string applies to all patterns. Object maps pattern to action.
  # =========================================================================
  permission = {
    # Read-only inspection — auto-approved
    read = {
      "*" = "allow";
      ".env" = "deny";
      ".env.*" = "deny";
      "secrets/**" = "deny";
      "**/vault.bin" = "deny";
      "**/id_ed25519" = "deny";
      "**/id_rsa" = "deny";
    };
    glob = "allow";
    grep = "allow";
    skill = "allow";

    # Bash — broad ask, narrow allows for safe queries, denies for destructive
    bash = {
      "git status*" = "allow";
      "git log*" = "allow";
      "git diff*" = "allow";
      "git show*" = "allow";
      "git branch*" = "allow";
      "git remote*" = "allow";
      "tree*" = "allow";
      "wc*" = "allow";
      "find*" = "allow";
      "gh run list*" = "allow";
      "gh run view*" = "allow";
      "git push*" = "deny";
      "git reset --hard*" = "deny";
      "rm -rf*" = "deny";
      "*" = "ask";
    };

    edit = "ask";
    write = "ask";
    task = "ask";
    webfetch = "ask";
  };

  # =========================================================================
  # Formatter overrides — hermetic store paths
  # =========================================================================
  formatter = {
    nixfmt = {
      command = [
        (lib.getExe pkgs.nixfmt)
        "$FILE"
      ];
    };
    shfmt = {
      command = [
        (lib.getExe pkgs.shfmt)
        "-w"
        "$FILE"
      ];
    };
  };

  # =========================================================================
  # LSP overrides — hermetic store paths
  # =========================================================================
  lsp = {
    nixd = {
      command = [ (lib.getExe pkgs.nil) ];
    };
  };
}
