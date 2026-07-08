#!/usr/bin/env bash
# Konductor plugin hook — PreToolUse(Bash) tmux guard.
#
# Reads the hook JSON blob on stdin, inspects proposed Bash commands that
# invoke tmux, and emits advisory context (never blocks; exit 0 always)
# when a command mutates structure outside the claude:* namespace or sends
# keys to a user pane without prior announcement.
#
# Soft guardrail: warns, never rejects. User discretion overrides.
#
# Invoked by hooks/hooks.json as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/tmux-guard.sh"
#
# Kill switch (konductor-namespaced, NOT a Claude Code var):
#   KONDUCTOR_CLAUDE_HOOKS_DISABLE=1

[ "${KONDUCTOR_CLAUDE_HOOKS_DISABLE:-0}" = "1" ] && exit 0

# No tmux session — hook is inert.
[ -z "${TMUX:-}" ] && exit 0

input=$(cat 2>/dev/null || true)

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
else
  cmd="$input"
fi
[ -z "$cmd" ] && exit 0

# Only inspect tmux commands.
printf '%s' "$cmd" | grep -qE '(^|[;&|])\s*tmux\b' || exit 0

# Structural mutations targeting non-claude:* windows.
# split-window, new-window, kill-window, kill-pane, swap-pane, swap-window,
# break-pane, join-pane, move-window — any of these targeting a window/pane
# whose name does not start with claude: is a guardrail hit.
mutators='(split-window|kill-window|kill-pane|swap-pane|swap-window|break-pane|join-pane|move-window|move-pane)'
if printf '%s' "$cmd" | grep -Eq "$mutators"; then
  # If the command targets a claude: window, it's fine.
  if ! printf '%s' "$cmd" | grep -qE "claude:"; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"konductor/tmux: this command mutates tmux structure outside a claude:* window. Claude should only create/modify/destroy panes in windows named claude:<purpose>. If the user explicitly asked for this, proceed."}}\n'
    exit 0
  fi
fi

# send-keys to a non-claude:* target.
if printf '%s' "$cmd" | grep -qE 'send-keys'; then
  if ! printf '%s' "$cmd" | grep -qE "claude:"; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"konductor/tmux: send-keys targets a user pane. Announce the target pane and command in the conversation before executing. If already announced, proceed."}}\n'
    exit 0
  fi
fi

exit 0
