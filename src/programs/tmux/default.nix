# src/programs/tmux/default.nix
# Tmux configuration with catppuccin theme

{ pkgs, lib, ... }:

let

  # Inputrc for readline in tmux bash
  inputrc = pkgs.writeText "konductor-tmux-inputrc" ''
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

  # Bashrc for tmux shells
  tmuxBashrc = pkgs.writeText "konductor-tmux-bashrc" ''
    if [ -f ${pkgs.bash-completion}/share/bash-completion/bash_completion ]; then
      . ${pkgs.bash-completion}/share/bash-completion/bash_completion
    fi
    if [ -f ~/.bashrc ]; then
      . ~/.bashrc
    fi
  '';

  # Complete tmux configuration
  tmuxConfig = pkgs.writeText "konductor-tmux.conf" ''
    # Terminal settings
    set -g default-terminal "tmux-256color"
    set -g default-shell "${pkgs.bash}/bin/bash"
    set -g default-command "${pkgs.bash}/bin/bash --rcfile ${tmuxBashrc} -i"
    set -g history-limit 50000

    # Indexing
    set -g base-index 1
    setw -g pane-base-index 1

    # Vi mode
    setw -g mode-keys vi

    # Mouse support
    set -g mouse on

    # No escape delay
    set -g escape-time 0

    # Prefix key (Ctrl-a instead of Ctrl-b)
    set -g prefix C-a
    bind C-a send-prefix
    bind-key b send-keys C-b

    # Inputrc environment
    set-environment -g INPUTRC "${inputrc}"
    set -g update-environment "INPUTRC"

    # True color support
    set -ga terminal-overrides ",xterm-256color:RGB"
    set -as terminal-features ",xterm*:RGB"
    set -ag terminal-overrides ",alacritty:RGB"
    set -ag terminal-overrides ",kitty:RGB"
    set -ag terminal-overrides ",ghostty:RGB"

    # Focus events
    set -g focus-events on
    setw -g aggressive-resize on
    set -g status-interval 5

    # Activity monitoring
    setw -g monitor-activity off
    set -g visual-activity off
    set -g visual-bell off

    # Window management
    set -g renumber-windows on
    set -g status-position top

    # Reload configuration
    bind r run-shell 'tmux source-file "$KONDUCTOR_TMUX_CONF" && tmux display-message "Config reloaded!"'

    # Better split bindings
    unbind '"'
    unbind %
    bind '|' split-window -h -c "#{pane_current_path}"
    bind '\' split-window -h -c "#{pane_current_path}"
    bind - split-window -v -c "#{pane_current_path}"

    # Pane resizing
    bind -r H resize-pane -L 5
    bind -r J resize-pane -D 5
    bind -r K resize-pane -U 5
    bind -r L resize-pane -R 5

    # Window navigation
    bind Tab last-window
    bind -n M-H previous-window
    bind -n M-L next-window

    # Pane synchronization
    bind S set-window-option synchronize-panes\; display-message "Sync #{?pane_synchronized,ON,OFF}"

    # Pane management
    bind b break-pane
    bind j command-prompt -p "Join pane from:" "join-pane -s '%%'"

    # Clipboard integration
    set -s set-clipboard on
    set -g allow-passthrough on
    set -as terminal-features ',xterm*:clipboard'

    # Vi copy mode bindings
    bind-key -T copy-mode-vi 'v' send-keys -X begin-selection
    bind-key -T copy-mode-vi 'C-v' send-keys -X rectangle-toggle \; send -X begin-selection
    bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel
    bind-key -T copy-mode-vi Escape send-keys -X cancel

    # Platform-specific clipboard
    ${lib.optionalString pkgs.stdenv.isDarwin ''
    bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel 'pbcopy'
    ''}

    ${lib.optionalString pkgs.stdenv.isLinux ''
    bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel 'xsel -i --clipboard > /dev/null 2>&1 || wl-copy'
    ''}

    # Nested tmux session support (F12 toggle)
    color_status_text="colour245"
    color_window_off_status_bg="colour238"
    color_window_off_status_current_bg="colour254"
    color_light="white"
    color_dark="colour232"

    bind -T root F12 \
        set prefix None \;\
        set key-table off \;\
        set status-style "fg=$color_status_text,bg=$color_window_off_status_bg" \;\
        set window-status-current-format "#[fg=$color_window_off_status_bg,bg=$color_window_off_status_current_bg] #I:#W #" \;\
        set window-status-current-style "fg=$color_dark,bold,bg=$color_window_off_status_current_bg" \;\
        if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
        refresh-client -S \;\
        display-message "Outer tmux OFF - F12 to restore"

    bind -T off F12 \
        set -u prefix \;\
        set -u key-table \;\
        set -u status-style \;\
        set -u window-status-current-style \;\
        set -u window-status-current-format \;\
        refresh-client -S \;\
        display-message "Outer tmux ON"

    wg_is_keys_off="#[fg=$color_light,bg=colour196]#{?#{==:#{key-table},off}, [OFF] ,}#[default]"
    set -ag status-right "$wg_is_keys_off"

    # SSH indicator
    if-shell 'test -n "$SSH_CLIENT"' \
      'set -g status-position bottom; set -g status-right "#{hostname} | %H:%M"'

    # Catppuccin Macchiato theme
    set -g @catppuccin_flavour 'macchiato'
    set -g @catppuccin_window_status_style "rounded"
    set -g @catppuccin_window_left_separator ""
    set -g @catppuccin_window_right_separator " "
    set -g @catppuccin_window_middle_separator " █"
    set -g @catppuccin_window_number_position "right"
    set -g @catppuccin_window_default_fill "number"
    set -g @catppuccin_window_default_text "#W"
    set -g @catppuccin_window_current_fill "number"
    set -g @catppuccin_window_current_text "#W"
    set -g @catppuccin_status_modules_right "directory session"
    set -g @catppuccin_status_left_separator " "
    set -g @catppuccin_status_right_separator ""
    set -g @catppuccin_status_fill "icon"
    set -g @catppuccin_status_connect_separator "no"

    # Load plugins
    run-shell ${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux
    run-shell ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/catppuccin.tmux

    # Load local overrides if present
    if-shell '[ -f ~/.config/tmux/konductor-local.conf ]' \
      'source-file ~/.config/tmux/konductor-local.conf'
  '';

  # Wrapped tmux binary that uses our config
  tmuxWrapped = pkgs.writeShellScriptBin "tmux" ''
    if [ "$1" = "-f" ]; then
      exec ${pkgs.tmux}/bin/tmux "$@"
    else
      exec ${pkgs.tmux}/bin/tmux -f ${tmuxConfig} "$@"
    fi
  '';

in
{
  # Package list including wrapped tmux and plugins
  packages = [
    tmuxWrapped
    pkgs.tmuxp
    pkgs.tmuxPlugins.catppuccin
    pkgs.tmuxPlugins.sensible
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.xsel
    pkgs.wl-clipboard
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    pkgs.reattach-to-user-namespace
  ];

  # Shell hook to export config path (no env var duplication)
  shellHook = ''
    export KONDUCTOR_TMUX_CONF="${tmuxConfig}"
  '';

  # No extra env vars needed
  env = { };
}
