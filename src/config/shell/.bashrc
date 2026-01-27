# Konductor Bashrc
# Native bash config - read by nix wrapper for hermetic shell configuration
#
# This file is sourced by:
# - devshells (via shellHook in base.nix)
# - containers/VMs (via --rcfile)
# - neovim terminals (via wrapped bash)

# ===========================================================================
# User Bashrc (FIRST - so Konductor aliases take precedence)
# ===========================================================================
# Source user's bashrc first to get their base settings
# Konductor aliases defined below will override any conflicts
# Skip for non-interactive shells (runme, scripts) to avoid brew/starship errors
if [ -f "$HOME/.bashrc" ] && [ -z "$KONDUCTOR_BASHRC_SOURCED" ] && [[ $- == *i* ]]; then
  export KONDUCTOR_BASHRC_SOURCED=1
  source "$HOME/.bashrc"
fi

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
# Modern CLI Replacements
# ===========================================================================
alias ll='eza -la --git'
alias la='eza -la'
alias l='eza -l'
alias cat='bat --paging=never'
alias find='fd'
alias top='btm'
alias du='dust'
alias tree='eza --tree'

# ===========================================================================
# Safe Defaults
# ===========================================================================
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ===========================================================================
# Editor Shortcuts
# ===========================================================================
alias vi='nvim'
alias vim='nvim'

# ===========================================================================
# Git Shortcuts
# ===========================================================================
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias lg='lazygit'

# ===========================================================================
# Kubernetes
# ===========================================================================
alias k='kubecolor'
# Inherit kubectl completions for k alias
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

# ===========================================================================
# Task Automation
# ===========================================================================
alias mr='mise run'
alias rr='runme run'
alias rl='runme beta list'

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
# Skip direnv hook if already inside a nix shell to prevent double-loading
if command -v direnv >/dev/null 2>&1 && [ -z "$IN_NIX_SHELL" ]; then
  eval "$(direnv hook bash)"
fi

