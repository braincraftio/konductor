# Konductor Bashrc
# Native bash config - read by nix wrapper for hermetic shell configuration
#
# This file is sourced by:
# - devshells (via shellHook in base.nix)
# - containers/VMs (via --rcfile)
# - neovim terminals (via wrapped bash)

# ===========================================================================
# History Settings
# ===========================================================================
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
alias grep='rg'
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
alias k='kubectl'
# Inherit kubectl completions for k alias
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

# ===========================================================================
# Task Automation
# ===========================================================================
alias mr='mise run'

# ===========================================================================
# Prompt (Starship)
# ===========================================================================
if command -v starship >/dev/null 2>&1 && [ -t 0 ]; then
  eval "$(starship init bash)"
fi

# ===========================================================================
# Direnv
# ===========================================================================
# Skip direnv hook if already inside a nix shell to prevent double-loading
if command -v direnv >/dev/null 2>&1 && [ -z "$IN_NIX_SHELL" ]; then
  eval "$(direnv hook bash)"
fi

# ===========================================================================
# User Customization
# ===========================================================================
# Source user's bashrc last to allow personal overrides
# This respects user preferences while providing sensible defaults
if [ -f "$HOME/.bashrc" ] && [ -z "$KONDUCTOR_BASHRC_SOURCED" ]; then
  export KONDUCTOR_BASHRC_SOURCED=1
  source "$HOME/.bashrc"
fi
