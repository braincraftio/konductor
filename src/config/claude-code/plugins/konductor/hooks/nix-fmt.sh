#!/usr/bin/env bash
# Konductor plugin hook — PostToolUse(Edit|Write) Nix formatter.
#
# Reads the hook JSON blob on stdin and, when the edited file is a .nix file,
# formats it in place with nixfmt. Non-blocking: exit 0 always so a transient
# invalid intermediate edit never aborts the tool.
#
# Invoked by hooks/hooks.json as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/nix-fmt.sh"
# Plugin hooks run with the session PATH (konductor devshell provides nixfmt + jq);
# this script does not assume Nix runtimeInputs.
#
# Kill switch (konductor-namespaced, NOT a Claude Code var):
#   KONDUCTOR_CLAUDE_HOOKS_DISABLE=1

[ "${KONDUCTOR_CLAUDE_HOOKS_DISABLE:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null || true)

if command -v jq >/dev/null 2>&1; then
  file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)
else
  exit 0
fi
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.nix)
    if command -v nixfmt >/dev/null 2>&1; then
      nixfmt "$file" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
