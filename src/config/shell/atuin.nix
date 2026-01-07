# src/config/shell/atuin.nix
# Hermetic wrapper for Atuin - magical shell history
#
# Atuin replaces shell history with a SQLite database, providing:
# - Fuzzy search (fzf-style) with smart ranking
# - Workspace awareness (git repository scope)
# - Rich context (exit codes, duration, working directory, hostname)
# - Inspector view with charts and analytics
# - Optional encrypted sync across machines
#
# Design decisions:
# - LOCAL-ONLY by default (no sync/telemetry) for complete privacy
# - Sync can be enabled via ATUIN_SYNC=true environment variable
# - Config is maintained in native TOML (atuin.toml) for easy contribution
# - bash-preexec is bundled for Bash integration
#
# Keybindings:
#   Ctrl+R     - Open search, cycle filter modes (workspace/directory/session/host/global)
#   Ctrl+S     - Cycle search modes (fuzzy/prefix/fulltext/skim)
#   Ctrl+O     - Toggle Inspector view (charts, stats, command details)
#   Up Arrow   - Directory-scoped fuzzy search (quick recall)
#   Enter      - Execute selected command
#   Tab        - Copy to command line for editing
#   Esc        - Cancel and restore original command line
#   Ctrl+Y     - Copy selected command to clipboard
#   Alt+1-9    - Quick select by index
#
# Exports:
#   packages      - Atuin + bash-preexec packages
#   shellHook     - Initializes Atuin for the current shell
#   env           - Environment variables for Atuin configuration
#   configFile    - Nix store path to config.toml
#   configContent - Raw TOML content for other consumers

{ pkgs, ... }:

let
  # Config file - native TOML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "konductor-atuin-config";
    destination = "/config.toml";
    text = builtins.readFile ./atuin.toml;
  };

  # Shell initialization script
  # Handles Bash (with bash-preexec), Zsh, and Fish
  initScript = ''
    # ===========================================================================
    # Atuin Shell History - Magical fuzzy search with SQLite backend
    # ===========================================================================
    #
    # Keybindings:
    #   Ctrl+R  - Search history (cycles: workspace -> directory -> session -> host -> global)
    #   Ctrl+S  - Switch search mode (fuzzy -> prefix -> fulltext -> skim)
    #   Ctrl+O  - Toggle Inspector (charts, exit codes, usage patterns)
    #   Up      - Directory-scoped search (quick "what did I just run here?")
    #   Enter   - Execute selected command
    #   Tab     - Copy to command line for editing
    #   Esc     - Cancel search
    #
    # Local-only by default. To enable sync:
    #   export ATUIN_SYNC=true
    #   atuin login  # or: atuin register
    #
    # Commands:
    #   atuin stats          - View usage statistics
    #   atuin search <term>  - Non-interactive search
    #   atuin history list   - List recent history
    #   atuin doctor         - Check configuration
    #   atuin import auto    - Import existing shell history

    # Ensure XDG directories exist for Atuin state
    # Data stored: history.db, records.db, key, session
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
    mkdir -p "$XDG_DATA_HOME/atuin"

    # Force hermetic config from Konductor
    export ATUIN_CONFIG_DIR="${configFile}"

    # Handle sync enable/disable via environment variable
    if [[ "''${ATUIN_SYNC:-false}" == "true" ]]; then
      # User has opted into sync
      export ATUIN_SYNC_ADDRESS="''${ATUIN_SYNC_ADDRESS:-https://api.atuin.sh}"
      unset ATUIN_AUTO_SYNC  # Let config.toml handle it
    else
      # Local-only mode - ensure no sync happens
      export ATUIN_AUTO_SYNC="false"
    fi

    # Handle daemon enable/disable via environment variable
    if [[ "''${ATUIN_DAEMON:-false}" == "true" && "''${ATUIN_SYNC:-false}" == "true" ]]; then
      export ATUIN_DAEMON_ENABLED="true"
    else
      export ATUIN_DAEMON_ENABLED="false"
    fi

    # Initialize Atuin for current shell
    if command -v atuin >/dev/null 2>&1; then
      if [[ -n "$BASH_VERSION" ]]; then
        # Bash requires bash-preexec for preexec/precmd hooks
        if [[ :$SHELLOPTS: =~ :(vi|emacs): ]]; then
          if [[ -f "${pkgs.bash-preexec}/share/bash/bash-preexec.sh" ]]; then
            source "${pkgs.bash-preexec}/share/bash/bash-preexec.sh"
          fi
          eval "$(atuin init bash)"
        fi
      elif [[ -n "$ZSH_VERSION" ]]; then
        # Zsh has native preexec/precmd hooks via add-zsh-hook
        if [[ $options[zle] = on ]]; then
          eval "$(atuin init zsh)"
        fi
      fi
      # Note: Fish uses 'atuin init fish | source' but we're in bash/zsh here
    fi
  '';

in
{
  # Packages required for Atuin functionality
  # bash-preexec provides preexec/precmd hooks for Bash
  packages = [
    pkgs.atuin
    pkgs.bash-preexec
  ];

  # Unwrapped package for reference
  unwrapped = pkgs.atuin;

  # Config file path in nix store (for consumers like qcow2, oci)
  inherit configFile;

  # Raw TOML content for embedding in other configs
  configContent = builtins.readFile ./atuin.toml;

  # Shell hook for devshell integration
  # Use in devshells: ${config.shell.atuin.shellHook}
  shellHook = initScript;

  # Environment variables (static - dynamic ones set in shellHook)
  env = {
    ATUIN_CONFIG_DIR = "${configFile}";
  };

  # Metadata
  meta = {
    description = "Atuin shell history with Konductor configuration";
    configurable = true;
    syncDefault = false;
    homepage = "https://atuin.sh";
    keybindings = {
      "Ctrl+R" = "Search history, cycle filter modes";
      "Ctrl+S" = "Cycle search modes (fuzzy/prefix/fulltext/skim)";
      "Ctrl+O" = "Toggle Inspector view";
      "Up" = "Directory-scoped search";
      "Enter" = "Execute selected command";
      "Tab" = "Copy to command line for editing";
      "Esc" = "Cancel search";
    };
  };
}
