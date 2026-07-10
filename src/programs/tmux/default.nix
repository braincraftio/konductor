# k9/src/programs/tmux/default.nix
# Tmux configuration with catppuccin theme and productivity plugins
#
# V2: Complete rewrite based on DeepWiki research across 8 upstream repositories
# - NixOS/nixpkgs, catppuccin/tmux, tmux/tmux, christoomey/vim-tmux-navigator
# - tmux-plugins/tmux-resurrect, tmux-plugins/tmux-sensible, laktak/extrakto, tmux-plugins/tmux-yank
#
# Design Principles:
# - Hermetic Nix store paths for reproducibility
# - Collision-free keybindings (research-validated)
# - Seamless Neovim integration via vim-tmux-navigator
# - Session persistence for 12+ hour development sessions
# - Catppuccin Frappe theme with mauve accent

{ pkgs, lib, ... }:

let
  # ===========================================================================
  # SHARED CONFIGURATION (SSOT)
  # ===========================================================================

  # Import shared readline configuration (eliminates duplicate inputrc)
  readline = import ../../lib/readline.nix { inherit pkgs; };

  # Catppuccin Frappé palette SSOT (src/lib/theme.nix)
  theme = import ../../lib/theme.nix;

  # Import SSOT bashrc content (same as devshells, qcow2, OCI)
  bashrcContent = builtins.readFile ../../config/shell/.bashrc;

  # ===========================================================================
  # TMUX-WHICH-KEY (keybinding discovery popup)
  # ===========================================================================
  # Build the which-key init.tmux from our YAML config
  # Trigger: prefix + Space shows available keybindings

  whichKeyConfig = ./which-key.yaml;

  # Pre-build init.tmux at Nix build time (hermetic, no runtime YAML processing)
  # build.py takes positional arguments: config_file output_file
  # Note: build.py imports `from pyyaml.lib import yaml` - need to copy the pyyaml directory
  #
  # Upstream build.py hardcodes verbose `display -p` startup messages with no
  # config option to disable. Since init.tmux is our generated artifact (not
  # upstream code), we strip these from the output as a build post-process step.
  whichKeyBuilt =
    pkgs.runCommand "konductor-tmux-which-key"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p $out
        cp ${whichKeyConfig} $out/config.yaml
        cp ${pkgs.tmuxPlugins.tmux-which-key}/share/tmux-plugins/tmux-which-key/plugin/build.py $out/
        cp -rL ${pkgs.tmuxPlugins.tmux-which-key}/share/tmux-plugins/tmux-which-key/plugin/pyyaml $out/
        cd $out
        python3 build.py config.yaml init.tmux

        # Strip verbose startup messages from generated output
        # (upstream hardcodes these in build.py template with no disable option)
        sed -i '/^display -p/d' init.tmux
      '';

  # Bashrc for tmux shells - SSOT with devshells, qcow2, OCI
  # Sources bash-completion first, then the hermetic Konductor bashrc
  # Note: The SSOT bashrc handles user's ~/.bashrc sourcing internally
  tmuxBashrc = pkgs.writeText "konductor-tmux-bashrc" ''
    # Bash completion (must be first for tab completion to work)
    if [ -f ${pkgs.bash-completion}/share/bash-completion/bash_completion ]; then
      . ${pkgs.bash-completion}/share/bash-completion/bash_completion
    fi

    # Source direnv directly to get current environment from .envrc
    # This ensures tmux shells have KUBECONFIG, TALOSCONFIG, etc. regardless
    # of what environment the tmux server was started with.
    # Note: We use 'direnv export bash' (not the hook) because:
    # 1. The hook is skipped when IN_NIX_SHELL is set (see .bashrc:102)
    # 2. We want the environment NOW, not on directory change
    if command -v direnv >/dev/null 2>&1; then
      eval "$(direnv export bash 2>/dev/null)"
    fi

    # SSOT Konductor bashrc (same as devshells, qcow2, OCI)
    # This includes: history, shell options, aliases, starship, atuin, direnv hook
    ${bashrcContent}
  '';

  # ===========================================================================
  # KEYBINDING REFERENCE (for help system)
  # ===========================================================================

  keybindingReference = pkgs.writeText "konductor-tmux-keys.txt" ''
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                         KONDUCTOR TMUX KEYBINDINGS                           ║
    ╚══════════════════════════════════════════════════════════════════════════════╝

    PREFIX: Ctrl-a (C-a)

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ NAVIGATION (seamless with Neovim)                                            │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ C-h         Move to pane left          (works in Neovim too)                 │
    │ C-j         Move to pane down          (works in Neovim too)                 │
    │ C-k         Move to pane up            (works in Neovim too)                 │
    │ C-l         Move to pane right         (works in Neovim too)                 │
    │ C-\         Previous pane              (last active pane)                    │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ SPLITS                                                                       │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + |   Horizontal split (panes side by side)                           │
    │ prefix + \   Horizontal split (alternate)                                    │
    │ prefix + -   Vertical split (panes stacked)                                  │
    │ prefix + _   Vertical split (alternate)                                      │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ RESIZE (repeatable - hold prefix)                                            │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + H   Resize left 5 cells                                             │
    │ prefix + J   Resize down 5 cells                                             │
    │ prefix + K   Resize up 5 cells                                               │
    │ prefix + L   Resize right 5 cells                                            │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ WINDOWS                                                                      │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + Tab Last window (toggle)                                            │
    │ Alt-H        Previous window                                                 │
    │ Alt-L        Next window                                                     │
    │ Alt-1..9     Jump to window 1-9                                              │
    │ prefix + c   New window                                                      │
    │ prefix + ,   Rename window                                                   │
    │ prefix + &   Kill window (confirm)                                           │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PANE MANAGEMENT & NESTED TMUX                                                │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + b   Send Ctrl-b to inner tmux (activates inner's command mode)      │
    │ prefix + C-b Same as above (C-a C-b is intuitive)                            │
    │ prefix + B   Break pane to new window                                        │
    │ prefix + j   Join pane from another window                                   │
    │ prefix + S   Toggle pane synchronization                                     │
    │ prefix + z   Toggle pane zoom                                                │
    │ prefix + x   Kill pane (confirm)                                             │
    │ prefix + {   Swap pane up                                                    │
    │ prefix + }   Swap pane down                                                  │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ COPY MODE (prefix + [ to enter)                                              │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ v           Begin selection                                                  │
    │ V           Select line                                                      │
    │ C-v         Rectangle selection                                              │
    │ y           Yank to clipboard                                                │
    │ Escape      Cancel/exit                                                      │
    │ /           Search forward                                                   │
    │ ?           Search backward                                                  │
    │ n           Next match                                                       │
    │ N           Previous match                                                   │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLUGINS                                                                      │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + e   Extrakto (fuzzy extract text from pane)                         │
    │ prefix + F   tmux-fzf (fuzzy session/window/pane picker)                     │
    │ prefix + C-s Save session (resurrect)                                        │
    │ prefix + C-r Restore session (resurrect)                                     │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ UTILITY                                                                      │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ prefix + r   Reload configuration                                            │
    │ prefix + ?   Show this help                                                  │
    │ prefix + t   Show clock                                                      │
    │ prefix + :   Command prompt                                                  │
    │ F12          Toggle outer tmux OFF/ON (status bar grays when off)            │
    │              When OFF: all keys pass to inner tmux (SSH, nested sessions)    │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ NESTED TMUX PATTERN                                                          │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ Outer tmux: prefix = C-a (this session)                                      │
    │ Inner tmux: prefix = C-b (default, SSH remote, containers)                   │
    │                                                                              │
    │ To use inner tmux:                                                           │
    │   Option 1: C-a b  or  C-a C-b  (sends C-b to activate inner's commands)     │
    │   Option 2: F12 (disables outer, all keys go to inner, F12 again to restore) │
    └──────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ STATUS BAR MODULES                                                           │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ Left:   Session name (mauve)                                                │
    │ Right:  Git branch (green) → K8s context (blue) → AWS profile (peach)       │
    │         → Directory (mauve) → Time (mauve) → Host (SSH only)                │
    │                                                                              │
    │ Ambient modules only appear when active:                                     │
    │   Git:  Shows when in a git repository                                      │
    │   K8s:  Shows when kubectl is configured (context:namespace)                │
    │   AWS:  Shows when AWS_PROFILE is set                                       │
    ├──────────────────────────────────────────────────────────────────────────────┤
    │ Normal (Nerd Font):  Git ☸ K8s  AWS   Dir   Time   Host             │
    │ ASCII fallback:      [GIT] [K8S] [AWS] [D] [T] [H]                          │
    │                                                                              │
    │ Set KONDUCTOR_ASCII_MODE=1 for terminals without Nerd Font support.          │
    └──────────────────────────────────────────────────────────────────────────────┘

    Theme: Catppuccin Frappe (mauve accent)
    Press 'q' to close this help.
  '';

  # ===========================================================================
  # OSC 52 CLIPBOARD SCRIPT
  # ===========================================================================
  # Emits OSC 52 escape sequences to set the terminal clipboard.
  # Works universally across: ttyd (browser), kitty, alacritty, ghostty,
  # iTerm2, WezTerm, foot, and any terminal supporting OSC 52.
  # Eliminates dependency on xsel/wl-copy/pbcopy — the terminal itself
  # handles clipboard access, including browser Clipboard API via ttyd.
  #
  # Used by tmux-yank via @override_copy_command and by extrakto via
  # @extrakto_clip_tool. tmux's native set-clipboard also emits OSC 52,
  # but copy-pipe (used by tmux-yank) replaces it — this script restores
  # OSC 52 clipboard support through the copy-pipe pathway.

  osc52clip = pkgs.writeShellScriptBin "osc52clip" ''
    #!/usr/bin/env bash
    # Read stdin, base64 encode, emit OSC 52 to set terminal clipboard.
    # OSC 52 format: ESC ] 52 ; c ; <base64-data> ESC \
    #   c = clipboard selection (vs p = primary)
    #   ESC \ = ST (String Terminator)
    #
    # When running inside tmux, write to the tmux tty (the outer terminal)
    # via the passthrough sequence so OSC 52 reaches the actual terminal
    # emulator (ttyd, kitty, etc.) rather than being consumed by tmux.

    data=$(cat)
    encoded=$(printf '%s' "$data" | base64 -w 0 2>/dev/null || printf '%s' "$data" | base64 2>/dev/null)

    # Write OSC 52 directly to the controlling terminal (/dev/tty).
    # copy-pipe runs this command with stdin piped from the selection
    # and stdout NOT connected to the terminal. Writing to stdout would
    # send the escape sequence into tmux's pipe, not to ttyd/xterm.js.
    # /dev/tty always refers to the controlling terminal of the process.
    printf '\e]52;c;%s\e\\' "$encoded" > /dev/tty
  '';

  # ===========================================================================
  # TMUX CONFIGURATION
  # ===========================================================================

  tmuxConfig = pkgs.writeText "konductor-tmux.conf" ''
    # =========================================================================
    # TERMINAL SETTINGS
    # =========================================================================
    # Override sensible's screen-256color with tmux-256color for better support
    set -g default-terminal "tmux-256color"
    set -g default-shell "${pkgs.bash}/bin/bash"
    set -g default-command "${pkgs.bash}/bin/bash --rcfile ${tmuxBashrc} -i"

    # Research: sensible sets history-limit to 50000, we match for explicitness
    set -g history-limit 50000

    # Indexing starts at 1 (keyboard layout alignment - 1 is left of 2)
    set -g base-index 1
    setw -g pane-base-index 1

    # Vi mode for copy-mode (muscle memory with Neovim)
    setw -g mode-keys vi

    # Mouse support
    set -g mouse on

    # Research: escape-time 0 is CRITICAL for Neovim (sensible also sets this)
    # Explicit for documentation - eliminates escape sequence delay
    set -g escape-time 0

    # Prefix key: Ctrl-a (home row, less pinky strain than Ctrl-b)
    set -g prefix C-a
    bind C-a send-prefix

    # Inputrc environment for readline (uses shared SSOT)
    set-environment -g INPUTRC "${readline.path}"

    # Note: We don't use update-environment for KUBECONFIG etc. because it requires
    # hardcoding variable names. Instead, tmux shells source direnv directly in
    # tmuxBashrc to get the current environment from .envrc.

    # =========================================================================
    # TRUE COLOR SUPPORT
    # =========================================================================
    # Research: Complete terminal coverage from DeepWiki analysis

    # terminal-features: Named capabilities (tmux 3.2+)
    set -as terminal-features ",xterm*:RGB"
    set -as terminal-features ",tmux*:RGB"
    set -as terminal-features ",alacritty:RGB"
    set -as terminal-features ",kitty:RGB"
    set -as terminal-features ",ghostty:RGB"
    set -as terminal-features ",foot:RGB"
    set -as terminal-features ",wezterm:RGB"

    # terminal-overrides: Individual terminfo overrides (broader compatibility)
    set -ga terminal-overrides ",xterm-256color:RGB"
    set -ag terminal-overrides ",alacritty:RGB"
    set -ag terminal-overrides ",kitty:RGB"
    set -ag terminal-overrides ",ghostty:RGB"
    set -ag terminal-overrides ",iTerm.app*:RGB"
    set -ag terminal-overrides ",iTerm2*:RGB"
    set -ag terminal-overrides ",foot*:RGB"
    set -ag terminal-overrides ",wezterm*:RGB"
    set -ag terminal-overrides ",*256col*:RGB"

    # =========================================================================
    # WINDOW & PANE BEHAVIOR
    # =========================================================================
    # Research: focus-events is event-driven since tmux 3.3, consistent ordering
    # Required for Neovim FocusGained/FocusLost autocmds (autoread, etc.)
    set -g focus-events on

    # Multi-device attach: size windows to the most recently active client
    # instead of the smallest attached client. A phone peeking at a session
    # no longer shrinks the desktop view (durable web sessions attach from
    # laptop / tablet / desktop concurrently).
    set -g window-size latest
    setw -g aggressive-resize on
    set -g status-interval 5
    set -g renumber-windows on
    set -g status-position top

    # Activity monitoring disabled (less visual noise for focused development)
    setw -g monitor-activity off
    set -g visual-activity off
    set -g visual-bell off

    # =========================================================================
    # CLIPBOARD INTEGRATION
    # =========================================================================
    # Research: OSC 52 + external tools (tmux-yank) coexist well
    # set-clipboard 'on': Accept OSC 52 sequences AND set terminal clipboard
    set -s set-clipboard on
    set -g allow-passthrough on
    set -as terminal-features ',xterm*:clipboard'

    # =========================================================================
    # KEY BINDINGS - COLLISION-FREE (Research-validated)
    # =========================================================================
    # Principles:
    # 1. Lowercase for non-destructive actions
    # 2. Uppercase/Shift for destructive or alternate actions
    # 3. No binding conflicts between core and plugins

    # -------------------------------------------------------------------------
    # Configuration Management
    # -------------------------------------------------------------------------
    # Reload config with feedback
    bind r run-shell 'tmux source-file "$KONDUCTOR_TMUX_CONF" && tmux display-message "Config reloaded!"'

    # Help: Show keybinding reference
    bind ? display-popup -E -w 80 -h 40 'cat "$KONDUCTOR_TMUX_KEYS"'

    # -------------------------------------------------------------------------
    # Splits - Intuitive visual mnemonics
    # -------------------------------------------------------------------------
    unbind '"'
    unbind %
    bind '|' split-window -h -c "#{pane_current_path}"  # Vertical line = horizontal split
    bind '\' split-window -h -c "#{pane_current_path}"  # Same (easier to type)
    bind '-' split-window -v -c "#{pane_current_path}"  # Horizontal line = vertical split
    bind '_' split-window -v -c "#{pane_current_path}"  # Same with shift

    # -------------------------------------------------------------------------
    # Pane Resizing - Vim-style HJKL with repeat
    # -------------------------------------------------------------------------
    bind -r H resize-pane -L 5
    bind -r J resize-pane -D 5
    bind -r K resize-pane -U 5
    bind -r L resize-pane -R 5

    # -------------------------------------------------------------------------
    # Window Navigation
    # -------------------------------------------------------------------------
    bind Tab last-window                  # Quick toggle to last window
    bind -n M-H previous-window           # Alt-Shift-H: previous
    bind -n M-L next-window               # Alt-Shift-L: next

    # Alt-1 through Alt-9 for direct window access
    bind -n M-1 select-window -t 1
    bind -n M-2 select-window -t 2
    bind -n M-3 select-window -t 3
    bind -n M-4 select-window -t 4
    bind -n M-5 select-window -t 5
    bind -n M-6 select-window -t 6
    bind -n M-7 select-window -t 7
    bind -n M-8 select-window -t 8
    bind -n M-9 select-window -t 9

    # -------------------------------------------------------------------------
    # Pane Management & Nested Tmux Support
    # -------------------------------------------------------------------------
    # Nested tmux pattern: Outer uses C-a prefix, Inner uses C-b (default)
    # C-a b   -> sends C-b to inner tmux (activates inner's command mode)
    # C-a C-b -> same, more intuitive for users expecting C-b behavior
    bind b send-keys C-b                  # Send literal Ctrl-b to inner tmux
    bind C-b send-keys C-b                # Same (C-a C-b is intuitive)
    bind B break-pane                     # Break pane to new window (shift=destructive)
    bind j command-prompt -p "Join pane from:" "join-pane -s '%%'"

    # Pane synchronization toggle
    bind S set-window-option synchronize-panes\; display-message "Sync #{?pane_synchronized,ON,OFF}"

    # -------------------------------------------------------------------------
    # Copy Mode - Vim-aligned
    # -------------------------------------------------------------------------
    bind-key -T copy-mode-vi 'v' send-keys -X begin-selection
    bind-key -T copy-mode-vi 'V' send-keys -X select-line
    bind-key -T copy-mode-vi 'C-v' send-keys -X rectangle-toggle \; send -X begin-selection
    bind-key -T copy-mode-vi Escape send-keys -X cancel

    # Search bindings (vim-like incremental search)
    bind-key -T copy-mode-vi '/' command-prompt -i -p "search down" "send -X search-forward-incremental \"%%%\""
    bind-key -T copy-mode-vi '?' command-prompt -i -p "search up" "send -X search-backward-incremental \"%%%\""

    # =========================================================================
    # CATPPUCCIN THEME - Frappe with Mauve Accent
    # =========================================================================
    # IMPORTANT: All @catppuccin options must be set BEFORE run-shell
    # Research: catppuccin 2.1.3 API is stable for @catppuccin_* options
    #
    # ASCII FALLBACK MODE:
    # Set KONDUCTOR_ASCII_MODE=1 for terminals without Nerd Font support.
    # This switches to ASCII icons and basic separators.

    set -g @catppuccin_flavor 'frappe'

    # -------------------------------------------------------------------------
    # Window Tabs - Rounded pill style (modern macOS/PopOS aesthetic)
    # -------------------------------------------------------------------------
    # CRITICAL: Must use run-shell (blocking) NOT if-shell (async)!
    # if-shell runs asynchronously - catppuccin loads BEFORE if-shell completes.
    # run-shell blocks until the command finishes, ensuring options are set first.
    #
    # Rounded style:  (U+E0B6) left,  (U+E0B4) right
    # ASCII mode: use "basic" style + parentheses separators
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_window_status_style "basic"; else tmux set -g @catppuccin_window_status_style "rounded"; fi'

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
    # Status Modules - Rounded pill separators (consistent with window style)
    # -------------------------------------------------------------------------
    # CRITICAL: Using run-shell (blocking) for the same reason as window style.
    # Status modules DON'T have a "style" option - must set separators explicitly.
    # connect_separator "yes" = backgrounds blend for continuous pill shape
    # Glyphs:  (U+E0B6) left rounded,  (U+E0B4) right rounded
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_status_left_separator "("; else tmux set -g @catppuccin_status_left_separator ""; fi'
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_status_middle_separator "|"; else tmux set -g @catppuccin_status_middle_separator ""; fi'
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_status_right_separator ")"; else tmux set -g @catppuccin_status_right_separator ""; fi'
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_status_connect_separator "no"; else tmux set -g @catppuccin_status_connect_separator "no"; fi'

    # Module colors - ALL mauve for cohesive purple look
    set -g @catppuccin_session_color "#{@thm_mauve}"
    set -g @catppuccin_directory_color "#{@thm_mauve}"
    set -g @catppuccin_date_time_color "#{@thm_mauve}"
    set -g @catppuccin_host_color "#{@thm_mauve}"

    # -------------------------------------------------------------------------
    # MODULE ICONS - ASCII fallback for non-Nerd-Font terminals
    # -------------------------------------------------------------------------
    # Using run-shell with printf for Unicode escapes (Nix strings lose glyphs)
    # ASCII mode: [S] [D] [T] [H]
    # Normal mode: Nerd Font icons (U+F120=terminal, U+F07B=folder, U+F017=clock, U+F233=server)

    # SESSION MODULE - dark text on mauve
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_session_icon "[S]"; else tmux set -g @catppuccin_session_icon ""; fi'
    set -g @catppuccin_session_text " #S"
    set -g @catppuccin_status_session_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_session_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_session_text_bg "#{@thm_mauve}"

    # DIRECTORY MODULE - dark text on mauve
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_directory_icon "[D]"; else tmux set -g @catppuccin_directory_icon ""; fi'
    set -g @catppuccin_directory_text " #{b:pane_current_path}"
    set -g @catppuccin_status_directory_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_directory_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_directory_text_bg "#{@thm_mauve}"

    # DATE/TIME MODULE - dark text on mauve
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_date_time_icon "[T]"; else tmux set -g @catppuccin_date_time_icon ""; fi'
    set -g @catppuccin_date_time_text " %I:%M"
    set -g @catppuccin_status_date_time_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_date_time_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_date_time_text_bg "#{@thm_mauve}"

    # HOST MODULE (SSH) - dark text on mauve
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_host_icon "[H]"; else tmux set -g @catppuccin_host_icon ""; fi'
    set -g @catppuccin_host_text " #H"
    set -g @catppuccin_status_host_icon_fg "#{@thm_crust}"
    set -g @catppuccin_status_host_text_fg "#{@thm_crust}"
    set -g @catppuccin_status_host_text_bg "#{@thm_mauve}"

    # =========================================================================
    # CUSTOM MODULES - Slow-Churn Ambient Awareness
    # =========================================================================
    # These modules show context that rarely changes during a session:
    # - Kubernetes context/namespace (when KUBECONFIG set)
    # - Git branch (when in git repo)
    # - Cloud profile (when AWS_PROFILE set)
    #
    # Philosophy: Removed from starship prompt (fast-churn, per-command),
    # placed here in tmux status bar (slow-churn, 5-second refresh).
    #
    # Custom modules use catppuccin's module system:
    # 1. Define icon/color/text BEFORE catppuccin.tmux loads
    # 2. Source status_module.conf AFTER catppuccin.tmux to create module
    # 3. Use #{E:@catppuccin_status_MODULE} in status-right
    #
    # Research: #(command) output is cached per status-interval (5s)

    # -------------------------------------------------------------------------
    # KUBERNETES MODULE - blue accent (k8s branding)
    # -------------------------------------------------------------------------
    # Shows context:namespace (hides namespace if "default")
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_kube_icon "[K8S] "; else tmux set -g @catppuccin_kube_icon "☸ "; fi'
    set -g @catppuccin_kube_color "#{@thm_blue}"
    # Smart display: context:namespace, or just context if namespace is "default"
    set -g @catppuccin_kube_text " #(kubectl config current-context 2>/dev/null)"

    # -------------------------------------------------------------------------
    # GIT BRANCH MODULE - green accent (git branding)
    # -------------------------------------------------------------------------
    # Shows branch name (truncated to 20 chars)
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_git_icon "[GIT]"; else tmux set -g @catppuccin_git_icon "󰊢"; fi'
    set -g @catppuccin_git_color "#{@thm_green}"
    set -g @catppuccin_git_text " #(cd \"#{pane_current_path}\" && git branch --show-current 2>/dev/null | head -c20)"

    # -------------------------------------------------------------------------
    # AWS PROFILE MODULE - peach/orange accent (AWS branding)
    # -------------------------------------------------------------------------
    # Shows AWS_PROFILE when set
    run-shell 'if [ -n "$KONDUCTOR_ASCII_MODE" ]; then tmux set -g @catppuccin_aws_icon "[AWS]"; else tmux set -g @catppuccin_aws_icon "󰸏"; fi'
    set -g @catppuccin_aws_color "#{@thm_peach}"
    set -g @catppuccin_aws_text " #(echo $AWS_PROFILE)"

    # -------------------------------------------------------------------------
    # Pane Borders
    # -------------------------------------------------------------------------
    set -g @catppuccin_pane_border_style "fg=#{@thm_surface_1}"
    set -g @catppuccin_pane_active_border_style "fg=#{@thm_mauve}"

    # =========================================================================
    # PLUGIN CONFIGURATION (must precede plugin loading)
    # =========================================================================

    # -------------------------------------------------------------------------
    # vim-tmux-navigator: Seamless Neovim/tmux navigation
    # -------------------------------------------------------------------------
    # Research: is_vim pattern handles nvim, vim, vi, vimdiff, view, gvim, lvim, vimx, fzf
    set -g @vim_navigator_mapping_left "C-h"
    set -g @vim_navigator_mapping_right "C-l"
    set -g @vim_navigator_mapping_up "C-k"
    set -g @vim_navigator_mapping_down "C-j"
    set -g @vim_navigator_mapping_prev "C-\\"

    # -------------------------------------------------------------------------
    # extrakto: Fuzzy text extraction
    # -------------------------------------------------------------------------
    # FIXED: Changed from "tab" to "e" to avoid prefix+Tab collision
    # Mnemonic: 'e' for extract
    set -g @extrakto_key "e"
    set -g @extrakto_split_size "15"
    set -g @extrakto_clip_tool "${osc52clip}/bin/osc52clip"
    set -g @extrakto_fzf_tool "${pkgs.fzf}/bin/fzf"
    set -g @extrakto_fzf_layout "reverse"
    set -g @extrakto_filter_order "word line path url quote"

    # -------------------------------------------------------------------------
    # tmux-fzf: Fuzzy session/window management
    # -------------------------------------------------------------------------
    TMUX_FZF_LAUNCH_KEY="F"
    set -g @tmux-fzf-launch-key "F"

    # -------------------------------------------------------------------------
    # tmux-yank: Enhanced clipboard via OSC 52
    # -------------------------------------------------------------------------
    # @override_copy_command takes priority over all platform detection
    # (pbcopy, wl-copy, xsel, xclip). osc52clip emits OSC 52 escape
    # sequences which work universally: ttyd (browser clipboard), kitty,
    # alacritty, ghostty, iTerm2, WezTerm, foot, and any OSC 52 terminal.
    set -g @override_copy_command '${osc52clip}/bin/osc52clip'
    set -g @yank_selection 'clipboard'
    set -g @yank_selection_mouse 'clipboard'
    set -g @yank_with_mouse 'on'

    # -------------------------------------------------------------------------
    # tmux-resurrect: Session persistence
    # -------------------------------------------------------------------------
    # Research: @resurrect-strategy-nvim 'session' integrates with :mksession
    set -g @resurrect-capture-pane-contents 'on'
    set -g @resurrect-strategy-nvim 'session'
    set -g @resurrect-processes 'nvim vim ssh "~rails server" "~npm start"'

    # -------------------------------------------------------------------------
    # tmux-continuum: Automatic session saving
    # -------------------------------------------------------------------------
    # Research: 15 minute interval is recommended balance
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '15'

    # =========================================================================
    # LOAD PLUGINS
    # =========================================================================
    # Order: sensible -> theme -> navigation -> clipboard -> productivity -> persistence

    # Core (sets baseline defaults - respects our explicit settings)
    run-shell ${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux

    # Theme (must be after sensible, before status bar layout)
    run-shell ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/catppuccin.tmux

    # Create custom status modules (MUST be after catppuccin.tmux loads)
    # Each module requires setting MODULE_NAME then sourcing status_module.conf
    %hidden MODULE_NAME="kube"
    source ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/utils/status_module.conf
    %hidden MODULE_NAME="git"
    source ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/utils/status_module.conf
    %hidden MODULE_NAME="aws"
    source ${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin/utils/status_module.conf

    # Neovim Integration
    run-shell ${pkgs.tmuxPlugins.vim-tmux-navigator}/share/tmux-plugins/vim-tmux-navigator/vim-tmux-navigator.tmux
    run-shell ${pkgs.tmuxPlugins.vim-tmux-focus-events}/share/tmux-plugins/vim-tmux-focus-events/focus-events.tmux

    # Clipboard & Productivity
    run-shell ${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank/yank.tmux
    run-shell ${pkgs.tmuxPlugins.extrakto}/share/tmux-plugins/extrakto/extrakto.tmux
    run-shell ${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/main.tmux

    # Session Persistence (resurrect MUST be before continuum)
    run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux

    # Which-key (keybinding discovery - prefix + Space)
    # Unbind default next-layout to free Space for which-key
    unbind Space
    source-file ${whichKeyBuilt}/init.tmux

    # =========================================================================
    # STATUS BAR LAYOUT (must be AFTER catppuccin loads)
    # =========================================================================
    set -g status-left-length 100
    set -g status-right-length 200
    set -g status-justify left

    # Left: session module
    set -g status-left '#{E:@catppuccin_status_session}'

    # Right: ambient context + directory + time
    # Order: git -> kube -> aws -> directory -> time
    # Custom modules only render when their #(command) returns content
    set -g status-right '#{E:@catppuccin_status_git}#{E:@catppuccin_status_kube}#{E:@catppuccin_status_aws}#{E:@catppuccin_status_directory}#{E:@catppuccin_status_date_time}'

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
    # F12 disables outer tmux, grays status bar, allows inner tmux to receive keys
    # Colors are Nix-interpolated from src/lib/theme.nix (SSOT) because tmux
    # @thm_* theme variables don't expand reliably in bind context.

    bind -T root F12 \
        set prefix None \;\
        set key-table off \;\
        set status-style "fg=${theme.ui.inactiveForeground},bg=${theme.ui.inactiveBackground}" \;\
        set window-status-current-style "fg=${theme.ui.activeForeground},bg=${theme.ui.activeBackground}" \;\
        refresh-client -S \;\
        display-message "Outer tmux OFF - F12 to restore"

    # F12 again re-enables outer tmux
    bind -T off F12 \
        set -u prefix \;\
        set -u key-table \;\
        set -u status-style \;\
        set -u window-status-current-style \;\
        refresh-client -S \;\
        display-message "Outer tmux ON"

    # =========================================================================
    # DISCOVERABILITY
    # =========================================================================
    # Note: Removed session-created hook because it shows "(null):0:" prefix
    # when the session name isn't set yet. Users can press prefix + ? for help.
    # The status bar modules are self-documenting.

    # =========================================================================
    # LOCAL OVERRIDES
    # =========================================================================
    # Users can customize in ~/.config/tmux/konductor-local.conf
    if-shell '[ -f ~/.config/tmux/konductor-local.conf ]' \
      'source-file ~/.config/tmux/konductor-local.conf'
  '';

  # ===========================================================================
  # WRAPPED TMUX BINARY
  # ===========================================================================
  # Smart session management using native tmux flags:
  # - Default session name: "k9"
  # - `tmux` (no args) → attach to k9 or create it (via new-session -A)
  # - `tmux <command>` → pass through with our config
  # - `tmux -f custom.conf` → bypass our config entirely
  #
  # Key insight from man page: new-session -A behaves like attach-session
  # if the session already exists, eliminating manual has-session checks.
  #
  # Per tmux(1): "the shortest unambiguous form of a command is accepted"
  # So we detect ANY non-flag argument as a potential command/shortcut.

  tmuxWrapped = pkgs.writeShellScriptBin "tmux" ''
    TMUX_BIN="${pkgs.tmux}/bin/tmux"
    TMUX_CONF="${tmuxConfig}"
    SESSION_NAME="k9"

    # Check if ANY argument is -f (bypass our config entirely)
    for arg in "$@"; do
      if [ "$arg" = "-f" ]; then
        exec "$TMUX_BIN" "$@"
      fi
    done

    # Check if ANY argument is a non-flag (potential command or shortcut)
    # tmux accepts shortest unambiguous command prefixes (e.g., "att" for attach)
    # so we can't enumerate all possibilities - just detect non-flag args
    for arg in "$@"; do
      case "$arg" in
        -*) ;; # Flag argument, keep checking
        *)
          # Non-flag argument found - pass through as potential command
          exec "$TMUX_BIN" -f "$TMUX_CONF" "$@"
          ;;
      esac
    done

    # Only flags or no args: use default k9 session with attach-or-create
    # -A flag: attach to session if it exists, otherwise create it
    exec "$TMUX_BIN" -f "$TMUX_CONF" "$@" new-session -A -s "$SESSION_NAME"
  '';

in
{
  # ===========================================================================
  # MODULE EXPORTS
  # ===========================================================================

  # Package list including wrapped tmux, plugins, and dependencies
  packages = [
    tmuxWrapped
    # tmuxp removed: broken on nixpkgs master (libtmux version mismatch)

    # Core Plugins
    pkgs.tmuxPlugins.sensible
    pkgs.tmuxPlugins.catppuccin
    pkgs.tmuxPlugins.vim-tmux-navigator
    pkgs.tmuxPlugins.vim-tmux-focus-events
    pkgs.tmuxPlugins.yank
    pkgs.tmuxPlugins.extrakto
    pkgs.tmuxPlugins.tmux-fzf

    # Session Persistence
    pkgs.tmuxPlugins.resurrect
    pkgs.tmuxPlugins.continuum

    # Keybinding Discovery
    pkgs.tmuxPlugins.tmux-which-key

    # Dependencies
    pkgs.fzf

    # OSC 52 clipboard — universal clipboard via terminal escape sequences.
    # Replaces xsel/wl-clipboard/pbcopy with a single mechanism that works
    # in ttyd (browser), SSH, and all modern terminal emulators.
    osc52clip
  ];

  # No shell hook needed - all config is static Nix store paths
  shellHook = "";

  # Environment variables
  env = {
    KONDUCTOR_TMUX_CONF = "${tmuxConfig}";
    KONDUCTOR_TMUX_KEYS = "${keybindingReference}";
  };

  # Expose config for validation checks
  config = tmuxConfig;
}
