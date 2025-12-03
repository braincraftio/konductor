# src/programs/shell/bash.nix
# Bash configuration for neovim terminals

{ pkgs, ... }:

let

  # Inputrc for readline configuration
  bashInputrc = pkgs.writeText "konductor-bash-inputrc" ''
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

  # Neovim terminal bashrc - handles libvterm quirks
  nvimTerminalBashrcContent = ''
    export __MISE_NVIM_TERMINAL=1

    if command -v starship &>/dev/null; then
      eval "$(starship init bash)"
      export STARSHIP_SHELL="sh"
    else
      PS1='\033[01;32m\u@\h\033[00m:\033[01;34m\w\033[00m\$ '
    fi

    if [ -f ${pkgs.bash-completion}/share/bash-completion/bash_completion ]; then
      source ${pkgs.bash-completion}/share/bash-completion/bash_completion 2>/dev/null || true
    fi
  '';

  nvimTerminalBashrc = pkgs.writeTextFile {
    name = "konductor-nvim-terminal-bashrc";
    text = nvimTerminalBashrcContent;
    executable = false;
  };

  nvimTerminalBashWrapper = pkgs.writeShellScript "konductor-nvim-terminal-bash" ''
    export INPUTRC="${bashInputrc}"
    exec ${pkgs.rlwrap}/bin/rlwrap ${pkgs.bash}/bin/bash --rcfile ${nvimTerminalBashrc}
  '';

in
{
  inherit bashInputrc nvimTerminalBashrc nvimTerminalBashWrapper;
}
