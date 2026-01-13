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

  # Shell initialization script - sets up env vars, actual init in .bashrc
  initScript = ''
    # Atuin Shell History - SQLite-backed fuzzy search
    # Keybindings: Ctrl+R (search), Up (directory search), Ctrl+O (inspector)
    # Actual init happens in .bashrc for proper interactive shell context
    mkdir -p "''${XDG_DATA_HOME:-$HOME/.local/share}/atuin"
    export ATUIN_CONFIG_DIR="${configFile}"
    export BASH_PREEXEC_PATH="${pkgs.bash-preexec}/share/bash/bash-preexec.sh"
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

  # Environment variables
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
