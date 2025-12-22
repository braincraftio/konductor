# src/lib/shell-content.nix
# SSOT for shell configuration content strings
# Uses centralized env.nix and aliases.nix

let
  versions = import ./versions.nix;
  env = import ./env.nix;
  aliases = import ./aliases.nix;

in
{ lib }:
let
  # Convert aliases attrset to shell alias commands
  aliasesToShellCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "    alias ${name}='${value}'") aliases
  );

  # Common shell setup (history, options, prompts)
  commonShellSetup = ''
        [[ $- != *i* ]] && return

        # Shell history settings
        shopt -s histappend

        # Shell options
        shopt -s checkwinsize
        shopt -s globstar 2>/dev/null || true
        shopt -s cdspell 2>/dev/null || true

        # Aliases
    ${aliasesToShellCommands}

        # Starship prompt
        if command -v starship >/dev/null 2>&1 && [ -t 0 ]; then
          eval "$(starship init bash)"
        fi

        # Direnv
        if command -v direnv >/dev/null 2>&1; then
          eval "$(direnv hook bash)"
        fi
  '';

  # Environment variable exports for standalone shells (containers, VMs)
  envExports = ''
    # Locale
    export LANG=${env.LANG}
    export LC_ALL=${env.LC_ALL}

    # Editor
    export EDITOR=${env.EDITOR}
    export VISUAL=${env.VISUAL}
    export PAGER=${env.PAGER}

    # Terminal
    export TERM=${env.TERM}

    # History
    export HISTSIZE=${env.HISTSIZE}
    export HISTFILESIZE=${env.HISTFILESIZE}
    export HISTCONTROL=${env.HISTCONTROL}
  '';

in
{
  # Bashrc for devshells - env vars set by mkShell
  bashrcContentDevshell = commonShellSetup;

  # Bashrc for containers/VMs - includes env var exports
  bashrcContentStandalone = envExports + "\n" + commonShellSetup;

  # Bash profile content
  bashProfileContent = ''
    if [ -f ~/.bashrc ]; then
      source ~/.bashrc
    fi
  '';

  # Inputrc content
  inputrcContent = ''
    set enable-keypad on
    set input-meta on
    set output-meta on
    set convert-meta off
    "\e[A": previous-history
    "\e[B": next-history
    "\e[C": forward-char
    "\e[D": backward-char
    "\e[H": beginning-of-line
    "\e[F": end-of-line
    "\e[3~": delete-char
    set completion-ignore-case on
    set show-all-if-ambiguous on
    set colored-stats on
  '';

  # Gitconfig content
  gitconfigContent = ''
    [init]
        defaultBranch = main
    [core]
        editor = ${env.EDITOR}
        pager = ${env.PAGER}
    [color]
        ui = auto
    [pull]
        rebase = true
    [alias]
        st = status
        co = checkout
        br = branch
        ci = commit
        lg = log --oneline --graph --decorate
    [safe]
        directory = /opt/konductor
        directory = /workspace
        directory = *
  '';

  # NOTE: Starship config is SSOT in src/config/shell/starship.toml
  # Access via: config.shell.starship.configContent

  # Welcome message content
  welcomeMessageContent = ''
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║        Konductor Development Container       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "Languages:"
    echo "  Python ${versions.languages.python.display}  |  Go ${versions.languages.go.display}"
    echo "  Node.js ${versions.languages.node.display}  |  Rust ${versions.languages.rust.display}"
    echo ""
    echo "Editor: ${env.EDITOR} (Neovim with LSP, Telescope, etc.)"
    echo "Tools:  git, gh, lazygit, fzf, ripgrep, fd, bat"
    echo ""
    echo "Commands:"
    echo "  mise run help    - All available tasks"
    echo "  nvim             - Launch Neovim"
    echo ""
  '';
}
