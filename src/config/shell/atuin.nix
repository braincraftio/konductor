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
# - LOCAL-ONLY by default (auto_sync = false); `atuin login` + auto_sync opts in
# - Daemon autostarts: daemon-fuzzy search, output capture (via pty-proxy,
#   which `atuin init` re-execs the shell into), and agent thread capture
# - Agent integration lives in the harnesses, from the same pkgs.atuin:
#   Claude Code hooks + MCP (src/harness/claude-code), OpenCode server plugin
#   + MCP (src/harness/opencode). Nothing runs `atuin hook install`.
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

{
  pkgs,
  lib,
  # Module options konductor.atuin.{package,settings}. settings merges over
  # atuin.toml with lib.recursiveUpdate; lists replace whole. Example escape
  # hatch: { pty_proxy.enabled = false; } drops the per-shell pty-proxy
  # process (and output capture with it).
  settings ? { },
  package ? pkgs.atuin,
  ...
}:

let
  finalSettings = lib.recursiveUpdate (builtins.fromTOML (builtins.readFile ./atuin.toml)) settings;

  # ATUIN_CONFIG_DIR names a directory holding config.toml.
  configFile = pkgs.runCommand "konductor-atuin-config" { } ''
    install -Dm644 ${(pkgs.formats.toml { }).generate "config.toml" finalSettings} "$out/config.toml"
  '';

  # Shell initialization script - creates data dir (needs $HOME at runtime)
  # ATUIN_CONFIG_DIR and KONDUCTOR_PREEXEC_PATH set via env attribute (static nix paths)
  # Note: Cannot use BASH_ prefix - bash reserves variables starting with BASH_
  initScript = ''
    # Atuin Shell History - SQLite-backed fuzzy search
    # Keybindings: Ctrl+R (search), Up (directory search), Ctrl+O (inspector)
    # Actual init happens in .bashrc for proper interactive shell context
    mkdir -p "''${XDG_DATA_HOME:-$HOME/.local/share}/atuin"
  '';

in
{
  # Packages required for Atuin functionality
  # bash-preexec provides preexec/precmd hooks for Bash
  packages = [
    package
    pkgs.bash-preexec
  ];

  inherit package;
  unwrapped = package;
  settings = finalSettings;

  # Directory holding the merged config.toml (ATUIN_CONFIG_DIR, home.file source)
  inherit configFile;

  # Konductor default TOML without module overrides (qcow2 skel)
  configContent = builtins.readFile ./atuin.toml;

  # Shell hook for devshell integration
  # Use in devshells: ${config.shell.atuin.shellHook}
  shellHook = initScript;

  # Environment variables (static nix paths)
  # Note: KONDUCTOR_PREEXEC_PATH instead of BASH_PREEXEC_PATH - bash reserves BASH_* variables
  env = {
    ATUIN_CONFIG_DIR = "${configFile}";
    KONDUCTOR_PREEXEC_PATH = "${pkgs.bash-preexec}/share/bash/bash-preexec.sh";
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
