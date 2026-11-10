#!/usr/bin/env bash
# Konductor plugin hook — PreToolUse(Bash) tmux guard.
#
# Reads the hook JSON blob on stdin, inspects proposed Bash commands that
# invoke tmux, and emits advisory context (never blocks; exit 0 always)
# when a command mutates structure outside the harness:* namespace or sends
# keys to a user pane without prior announcement.
#
# Soft guardrail: warns, never rejects. User discretion overrides.
#
# Invoked by hooks/hooks.json as:  bash "${CLAUDE_PLUGIN_ROOT}/hooks/tmux-guard.sh"
#
# Kill switch (konductor-namespaced, NOT a Claude Code var):
#   KONDUCTOR_CLAUDE_HOOKS_DISABLE=1

[[ "${KONDUCTOR_CLAUDE_HOOKS_DISABLE:-0}" = "1" ]] && exit 0

# No tmux session — hook is inert.
[[ -z "${TMUX:-}" ]] && exit 0

input=$(cat 2> /dev/null || true)

if command -v jq > /dev/null 2>&1; then
    cmd=$(printf '%s' "${input}" | jq -r '.tool_input.command // ""' 2> /dev/null || true)
else
    cmd="${input}"
fi
[[ -z "${cmd}" ]] && exit 0

# Only inspect tmux commands.
printf '%s' "${cmd}" | grep -qE '(^|[;&|])\s*tmux\b' || exit 0

# Structural mutations targeting non-harness:* windows.
# split-window, new-window, kill-window, kill-pane, swap-pane, swap-window,
# break-pane, join-pane, move-window — any of these targeting a window/pane
# whose name does not start with harness: is a guardrail hit.
mutators='(split-window|kill-window|kill-pane|swap-pane|swap-window|break-pane|join-pane|move-window|move-pane)'
if printf '%s' "${cmd}" | grep -Eq "${mutators}"; then
    # Session ownership is defined by the shared tmux skill.
    if ! printf '%s' "${cmd}" | grep -qE "harness:"; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"konductor/tmux: verify this structural mutation targets a window owned by the current session, named harness:<session-id>:<purpose>. The shared tmux skill defines ownership. If the user explicitly requested this change, proceed."}}\n'
        exit 0
    fi
fi

# send-keys to a non-harness:* target.
if printf '%s' "${cmd}" | grep -qE 'send-keys'; then
    if ! printf '%s' "${cmd}" | grep -qE "harness:"; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"konductor/tmux: send-keys targets a user pane. Announce the target pane and command in the conversation before executing. If already announced, proceed."}}\n'
        exit 0
    fi
fi

exit 0
