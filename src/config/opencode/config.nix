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
  # Permissions — ported from src/config/claude-code/permissions.nix
  # OpenCode uses action/resource/effect triples evaluated last-match-wins.
  # =========================================================================
  permissions = [
    # Read-only inspection — auto-approved
    {
      action = "read";
      resource = "*";
      effect = "allow";
    }
    {
      action = "glob";
      resource = "*";
      effect = "allow";
    }
    {
      action = "grep";
      resource = "*";
      effect = "allow";
    }

    # Safe git queries
    {
      action = "bash";
      resource = "git status*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "git log*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "git diff*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "git show*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "git branch*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "git remote*";
      effect = "allow";
    }

    # Safe filesystem inspection
    {
      action = "bash";
      resource = "tree*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "wc*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "find*";
      effect = "allow";
    }

    # Safe CI inspection
    {
      action = "bash";
      resource = "gh run list*";
      effect = "allow";
    }
    {
      action = "bash";
      resource = "gh run view*";
      effect = "allow";
    }

    # MCP tools — read-only queries
    {
      action = "skill";
      resource = "*";
      effect = "allow";
    }

    # Destructive operations — blocked
    {
      action = "bash";
      resource = "git push*";
      effect = "deny";
    }
    {
      action = "bash";
      resource = "git reset --hard*";
      effect = "deny";
    }
    {
      action = "bash";
      resource = "rm -rf*";
      effect = "deny";
    }

    # Secret material — blocked
    {
      action = "read";
      resource = ".env";
      effect = "deny";
    }
    {
      action = "read";
      resource = ".env.*";
      effect = "deny";
    }
    {
      action = "read";
      resource = "secrets/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "**/vault.bin";
      effect = "deny";
    }
    {
      action = "read";
      resource = "**/id_ed25519";
      effect = "deny";
    }
    {
      action = "read";
      resource = "**/id_rsa";
      effect = "deny";
    }

    # Everything else — prompt for approval
    {
      action = "edit";
      resource = "*";
      effect = "ask";
    }
    {
      action = "write";
      resource = "*";
      effect = "ask";
    }
    {
      action = "bash";
      resource = "*";
      effect = "ask";
    }
  ];

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
    nix = {
      command = [ (lib.getExe pkgs.nil) ];
    };
  };
}
