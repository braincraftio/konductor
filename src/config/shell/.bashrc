# Konductor Bashrc
# Native bash config - read by nix wrapper for hermetic shell configuration
#
# This file is sourced by:
# - devshells (via shellHook in base.nix)
# - containers/VMs (via --rcfile)
# - neovim terminals (via wrapped bash)

# ===========================================================================
# IDE Agent Terminal Guard
# ===========================================================================
# Skip interactive hooks for Windsurf/Cursor/VS Code agent terminals.
# These agents spawn terminals to run commands but the interactive hooks
# (starship, atuin, direnv) prevent clean shell exit, causing agent hangs.
# The agent-shell wrapper handles OSC 633 sequences for command completion.
#
# TRACING: Log to /tmp/konductor-bashrc.trace for debugging
_trace_bashrc() { echo "[$(date '+%H:%M:%S.%3N')] [bashrc] $*" >> /tmp/konductor-bashrc.trace; }
_trace_bashrc "=== .bashrc sourced: WINDSURF_CASCADE_TERMINAL=${WINDSURF_CASCADE_TERMINAL:-<unset>} ==="

if [[ -n "${WINDSURF_CASCADE_TERMINAL:-}" ]]; then
  _trace_bashrc "GUARD TRIGGERED: Skipping interactive hooks, returning early"
  return 0 2>/dev/null || exit 0
fi
_trace_bashrc "GUARD PASSED: Loading interactive hooks (starship, atuin, direnv)"

# ===========================================================================
# User Bashrc
# ===========================================================================
# Source user's bashrc to get their base settings
# Skip for non-interactive shells (runme, scripts) to avoid brew/starship errors
if [ -f "$HOME/.bashrc" ] && [ -z "$KONDUCTOR_BASHRC_SOURCED" ] && [[ $- == *i* ]]; then
  export KONDUCTOR_BASHRC_SOURCED=1
  source "$HOME/.bashrc"
fi

# Clear aliases that conflict with wrapper scripts in PATH
# Wrapper scripts provide TTY-aware behavior (bat for interactive, plain for pipes)
unalias cat 2>/dev/null || true
unalias grep 2>/dev/null || true

# ===========================================================================
# History Settings
# ===========================================================================
# Note: In the 'full' devshell, Atuin provides enhanced history with:
# - Fuzzy search (Ctrl+R)
# - Workspace-aware filtering
# - SQLite storage with rich context
# These native settings remain for fallback/compatibility.
HISTCONTROL=ignoreboth
shopt -s histappend

# ===========================================================================
# Shell Options
# ===========================================================================
shopt -s checkwinsize
shopt -s globstar 2>/dev/null || true
shopt -s cdspell 2>/dev/null || true

# ===========================================================================
# Safe Defaults (not provided by alias-wrappers.nix)
# ===========================================================================
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ===========================================================================
# Shortcuts (not provided by alias-wrappers.nix)
# ===========================================================================
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'

# Note: All standard aliases (ll, la, l, cat, find, top, du, tree, vi, vim, lg, k, mr, rr, rl)
# are provided as wrapper scripts by src/lib/alias-wrappers.nix with completions.
# This ensures hermetic behavior and special handling (e.g., cat with TTY detection).

# ===========================================================================
# Prompt (Starship)
# ===========================================================================
# Skip on dumb terminals (non-interactive shells, CI, piped commands)
if command -v starship >/dev/null 2>&1 && [ -t 0 ] && [[ "${TERM:-dumb}" != "dumb" ]]; then
  eval "$(starship init bash)"
fi

# ===========================================================================
# Atuin (Shell History)
# ===========================================================================
# Fuzzy search with Ctrl+R, directory-scoped Up arrow, inspector with Ctrl+O
# Requires bash-preexec for hooks. ATUIN_CONFIG_DIR set by devshell.
if command -v atuin >/dev/null 2>&1 && [ -t 0 ] && [[ "${TERM:-dumb}" != "dumb" ]]; then
  # Source bash-preexec if available (provides preexec/precmd hooks)
  # Note: Using KONDUCTOR_PREEXEC_PATH - bash reserves variables starting with BASH_
  if [ -n "$KONDUCTOR_PREEXEC_PATH" ] && [ -f "$KONDUCTOR_PREEXEC_PATH" ]; then
    source "$KONDUCTOR_PREEXEC_PATH"
  fi
  eval "$(atuin init bash)"
fi

# ===========================================================================
# Direnv
# ===========================================================================
# Silence direnv logging for IDE agents (must be set before hook)
export DIRENV_LOG_FORMAT="${DIRENV_LOG_FORMAT:-}"
# Skip direnv hook if already inside a nix shell to prevent double-loading
if command -v direnv >/dev/null 2>&1 && [ -z "$IN_NIX_SHELL" ]; then
  eval "$(direnv hook bash)"
fi

