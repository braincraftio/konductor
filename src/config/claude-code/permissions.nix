# src/config/claude-code/permissions.nix
# settings.json `permissions` object — the security surface, isolated for review.
#
# Evaluation order (Claude Code): deny → ask → allow; first match wins.
#   allow → auto-approved, no prompt
#   deny  → hard blocked
#   ask   → always prompt
#
# Shipped to the public, so the allow list is deliberately conservative
# (read-only inspection + safe git/gh queries) and the deny list blocks
# destructive git, recursive removal, and reads of secret material.

{
  defaultMode = "acceptEdits";

  allow = [
    # Read-only inspection
    "Read"
    "Glob"
    "Grep"
    "SendMessage"
    # Safe git queries
    "Bash(git status:*)"
    "Bash(git log:*)"
    "Bash(git diff:*)"
    "Bash(git show:*)"
    "Bash(git branch:*)"
    "Bash(git remote:*)"
    # Safe filesystem inspection
    "Bash(tree:*)"
    "Bash(wc:*)"
    "Bash(find:*)"
    # Safe CI inspection
    "Bash(gh run list:*)"
    "Bash(gh run view:*)"
    # No-auth MCP queries shipped enabled by konductor
    "mcp__deepwiki__ask_question"
  ];

  deny = [
    # Destructive git / filesystem
    "Bash(git push:*)"
    "Bash(git reset --hard:*)"
    "Bash(rm -rf:*)"
    # Secret material
    "Read(./.env)"
    "Read(./.env.*)"
    "Read(./secrets/**)"
    "Read(./**/vault.bin)"
    "Read(./**/id_ed25519)"
    "Read(./**/id_rsa)"
  ];

  ask = [ ];
}
