#!/usr/bin/env bash
# Konductor plugin hook — PreToolUse(Bash) secret scanner.
#
# Reads the hook JSON blob on stdin, inspects the proposed Bash command, and
# emits advisory context (never blocks; exit 0 always) when the command appears
# to embed a credential or read a secret file.
#
# Invoked by hooks/hooks.json as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/secret-scan.sh"
# Plugin hooks run with the session PATH (konductor devshell provides jq/grep);
# this script does not assume Nix runtimeInputs.
#
# Kill switch (konductor-namespaced, NOT a Claude Code var):
#   KONDUCTOR_CLAUDE_HOOKS_DISABLE=1

[ "${KONDUCTOR_CLAUDE_HOOKS_DISABLE:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null || true)

# jq is the normal path; degrade gracefully if absent.
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
else
  cmd="$input"
fi
[ -z "$cmd" ] && exit 0

patterns='(AWS_SECRET_ACCESS_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|GH_TOKEN|-----BEGIN [A-Z ]*PRIVATE KEY-----|password=|passwd=|token=[A-Za-z0-9]|\.env($|[^.])|/secrets/|vault\.bin|id_ed25519($|[^.])|id_rsa($|[^.]))'

if printf '%s' "$cmd" | grep -Eq "$patterns"; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"konductor: this Bash command may reference a secret or credential file. Confirm it does not leak sensitive material before running."}}\n'
fi

exit 0
