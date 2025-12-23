# src/programs/tmux/default.nix
# Tmux configuration with catppuccin theme and productivity plugins
# Design: Cohesive lavender theme, seamless neovim integration, fzf-powered workflows

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
    # =========================================================================
    # TERMINAL SETTINGS
    # =========================================================================
    set -g default-terminal "tmux-256color"
    set -g default-shell "${pkgs.bash}/bin/bash"
    set -g default-command "${pkgs.bash}/bin/bash --rcfile ${tmuxBashrc} -i"
    set -g history-limit 50000

    # Indexing starts at 1 (not 0)
    set -g base-index 1
    setw -g pane-base-index 1

    # Vi mode
    setw -g mode-keys vi

    # Mouse support
    set -g mouse on

    # No escape delay (critical for neovim)
    set -g escape-time 0

    # Prefix key: Ctrl-a (more ergonomic than Ctrl-b)
    set -g prefix C-a
    bind C-a send-prefix
    bind-key b send-keys C-b

    # Inputrc environment
    set-environment -g INPUTRC "${inputrc}"
    set -g update-environment "INPUTRC"

    # =========================================================================
    # TRUE COLOR SUPPORT
    # =========================================================================
    set -ga terminal-overrides ",xterm-256color:RGB"
    set -as terminal-features ",xterm*:RGB"
    set -ag terminal-overrides ",alacritty:RGB"
    set -ag terminal-overrides ",kitty:RGB"
    set -ag terminal-overrides ",ghostty:RGB"

    # =========================================================================
    # WINDOW & PANE BEHAVIOR
    # =========================================================================
    set -g focus-events on
    setw -g aggressive-resize on
    set -g status-interval 5
    set -g renumber-windows on
    set -g status-position top

    # Activity monitoring (disabled - less visual noise)
    setw -g monitor-activity off
    set -g visual-activity off
    set -g visual-bell off

    # =========================================================================
    # KEY BINDINGS
    # =========================================================================
    # Reload configuration
    bind r run-shell 'tmux source-file "$KONDUCTOR_TMUX_CONF" && tmux display-message "Config reloaded!"'

    # Split panes (| and - are intuitive)
    unbind '"'
    unbind %
    bind '|' split-window -h -c "#{pane_current_path}"
    bind '\' split-window -h -c "#{pane_current_path}"
    bind - split-window -v -c "#{pane_current_path}"

    # Pane resizing (vim-style with repeat)
    bind -r H resize-pane -L 5
    bind -r J resize-pane -D 5
    bind -r K resize-pane -U 5
    bind -r L resize-pane -R 5

    # Window navigation
    bind Tab last-window
    bind -n M-H previous-window
    bind -n M-L next-window

    # Pane synchronization toggle
    bind S set-window-option synchronize-panes\; display-message "Sync #{?pane_synchronized,ON,OFF}"

    # Pane management
    bind b break-pane
    bind j command-prompt -p "Join pane from:" "join-pane -s '%%'"

    # =========================================================================
    # CLIPBOARD INTEGRATION (enhanced by tmux-yank plugin)
    # =========================================================================
    set -s set-clipboard on
    set -g allow-passthrough on
    set -as terminal-features ',xterm*:clipboard'

    # Vi copy mode bindings (tmux-yank enhances these)
    bind-key -T copy-mode-vi 'v' send-keys -X begin-selection
    bind-key -T copy-mode-vi 'C-v' send-keys -X rectangle-toggle \; send -X begin-selection
    bind-key -T copy-mode-vi Escape send-keys -X cancel

    # =========================================================================
    # CATPPUCCIN THEME - Rounded style (pill-shaped separators)
    # =========================================================================
    # IMPORTANT: All @catppuccin options must be set BEFORE run-shell
    set -g @catppuccin_flavor 'frappe'

    # -------------------------------------------------------------------------
    # Window Tabs - Slanted style
    # -------------------------------------------------------------------------
    set -g @catppuccin_window_status_style "slanted"
    set -g @catppuccin_window_number_position "left"
    set -g @catppuccin_window_text " #W"
    set -g @catppuccin_window_number "#I"
    set -g @catppuccin_window_current_text " #W"
    set -g @catppuccin_window_current_number "#I"
    set -g @catppuccin_window_flags "none"

    # Current window: mauve/purple background
    set -g @catppuccin_window_current_number_color "#{@thm_mauve}"
    set -g @catppuccin_window_current_text_color "#{@thm_surface_0}"

    # -------------------------------------------------------------------------
    # Status Modules - Mauve theme with slanted separators
    # -------------------------------------------------------------------------
    # U+E0BC = \ backslash (flips color orientation)
    set -g @catppuccin_status_left_separator ""
    set -g @catppuccin_status_middle_separator ""
    set -g @catppuccin_status_right_separator ""
    set -g @catppuccin_status_connect_separator "no"

    # Module colors - ALL mauve for cohesive purple look
    set -g @catppuccin_session_color "#{@thm_mauve}"
    set -g @catppuccin_directory_color "#{@thm_mauve}"
    set -g @catppuccin_date_time_color "#{@thm_mauve}"
    set -g @catppuccin_host_color "#{@thm_mauve}"

    # SESSION MODULE - dark text on mauve
    set -g @catppuccin_session_icon "󰆍"
    set -g @catppuccin_session_text " #S"
    set -g @catppuccin_status_session_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_session_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_session_text_bg "#{@thm_mauve}"

    # DIRECTORY MODULE - dark text on mauve
    set -g @catppuccin_directory_icon "󰉋"
    set -g @catppuccin_directory_text " #{b:pane_current_path}"
    set -g @catppuccin_status_directory_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_directory_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_directory_text_bg "#{@thm_mauve}"

    # DATE/TIME MODULE - dark text on mauve
    set -g @catppuccin_date_time_icon "󰥔"
    set -g @catppuccin_date_time_text " %I:%M"
    set -g @catppuccin_status_date_time_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_date_time_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_date_time_text_bg "#{@thm_mauve}"

    # HOST MODULE (SSH) - dark text on mauve
    set -g @catppuccin_host_icon "󰒋"
    set -g @catppuccin_host_text " #H"
    set -g @catppuccin_status_host_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_host_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_host_text_bg "#{@thm_mauve}"

    # -------------------------------------------------------------------------
    # Pane Borders
    # -------------------------------------------------------------------------
    set -g @catppuccin_pane_border_style "fg=#{@thm_surface_1}"
    set -g @catppuccin_pane_active_border_style "fg=#{@thm_mauve}"

    # =========================================================================
    # PLUGIN CONFIGURATION (before loading)
    # =========================================================================

    # vim-tmux-navigator: Smart pane switching with awareness of Vim splits
    # Use Ctrl+hjkl to navigate between tmux panes AND neovim splits seamlessly
    set -g @vim_navigator_mapping_left "C-h"
    set -g @vim_navigator_mapping_right "C-l"
    set -g @vim_navigator_mapping_up "C-k"
    set -g @vim_navigator_mapping_down "C-j"
    set -g @vim_navigator_mapping_prev "C-\\"

    # extrakto: Fuzzy find and insert text from terminal
    # prefix + tab to activate
    set -g @extrakto_key "tab"
    set -g @extrakto_split_size "15"
    set -g @extrakto_clip_tool "auto"
    set -g @extrakto_fzf_tool "${pkgs.fzf}/bin/fzf"

    # tmux-fzf: Use fzf for tmux management
    # prefix + F to activate
    TMUX_FZF_LAUNCH_KEY="F"
    set -g @tmux-fzf-launch-key "F"

    # yank: Enhanced clipboard support
    set -g @yank_selection 'clipboard'
    set -g @yank_selection_mouse 'clipboard'

    # =========================================================================
    # LOAD PLUGINS
    # =========================================================================
    # Order matters: sensible first, then theme, then functionality plugins

    # Core
    run-shell ${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux

    # Theme
    run-shell ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/catppuccin.tmux

    # Neovim Integration
    run-shell ${pkgs.tmuxPlugins.vim-tmux-navigator}/share/tmux-plugins/vim-tmux-navigator/vim-tmux-navigator.tmux
    run-shell ${pkgs.tmuxPlugins.vim-tmux-focus-events}/share/tmux-plugins/vim-tmux-focus-events/focus-events.tmux

    # Productivity
    run-shell ${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank/yank.tmux
    run-shell ${pkgs.tmuxPlugins.extrakto}/share/tmux-plugins/extrakto/extrakto.tmux
    run-shell ${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/main.tmux

    # =========================================================================
    # STATUS BAR LAYOUT (must be AFTER catppuccin loads)
    # =========================================================================
    set -g status-left-length 100
    set -g status-right-length 200
    set -g status-justify left

    # Left: session module
    set -g status-left '#{E:@catppuccin_status_session}'

    # Right: directory + time
    set -g status-right '#{E:@catppuccin_status_directory}#{E:@catppuccin_status_date_time}'

    # SSH: add hostname, move bar to bottom for nested tmux visibility
    if-shell 'test -n "$SSH_CLIENT"' {
      set -g status-position bottom
      set -ag status-right '#{E:@catppuccin_status_host}'
    }

    # -------------------------------------------------------------------------
    # Additional Polish
    # -------------------------------------------------------------------------
    set -gF message-style "fg=#{@thm_mauve},bg=#{@thm_surface_0}"
    set -gF message-command-style "fg=#{@thm_peach},bg=#{@thm_surface_0}"
    set -gF mode-style "fg=#{@thm_crust},bg=#{@thm_mauve}"
    set -gF clock-mode-colour "#{@thm_mauve}"
    set -g clock-mode-style 12

    # =========================================================================
    # NESTED TMUX SUPPORT (F12 toggle)
    # =========================================================================
    bind -T root F12 \
        set prefix None \;\
        set key-table off \;\
        set status-style "fg=#{@thm_overlay_0},bg=#{@thm_surface_0}" \;\
        set window-status-current-style "fg=#{@thm_crust},bg=#{@thm_overlay_1}" \;\
        if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
        refresh-client -S \;\
        display-message "Outer tmux OFF - F12 to restore"

    bind -T off F12 \
        set -u prefix \;\
        set -u key-table \;\
        set -u status-style \;\
        set -u window-status-current-style \;\
        refresh-client -S \;\
        display-message "Outer tmux ON"

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
  # Package list including wrapped tmux and all plugins
  packages = [
    tmuxWrapped
    pkgs.tmuxp

    # Tmux Plugins
    pkgs.tmuxPlugins.sensible          # Sensible defaults
    pkgs.tmuxPlugins.catppuccin        # Theme
    pkgs.tmuxPlugins.vim-tmux-navigator # Seamless nvim/tmux navigation
    pkgs.tmuxPlugins.vim-tmux-focus-events # FocusGained/Lost for neovim
    pkgs.tmuxPlugins.yank              # Enhanced clipboard
    pkgs.tmuxPlugins.extrakto          # Fzf text extraction
    pkgs.tmuxPlugins.tmux-fzf          # Fzf for tmux management

    # Dependencies
    pkgs.fzf                           # Required by extrakto and tmux-fzf
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.xsel
    pkgs.wl-clipboard
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    pkgs.reattach-to-user-namespace
  ];

  # Shell hook to export config path
  shellHook = ''
    export KONDUCTOR_TMUX_CONF="${tmuxConfig}"
  '';

  # No extra env vars needed
  env = { };
}
