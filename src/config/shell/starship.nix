# src/config/shell/starship.nix
# Starship prompt configuration wrapper
#
# Config is defined inline (no separate file needed for this simple config).
# The wrapper forces config via STARSHIP_CONFIG env var with no escape hatch.

{ pkgs }:

let
  configContent = ''
    format = """
    $username\
    $hostname\
    $directory\
    $git_branch\
    $git_status\
    $python\
    $golang\
    $nodejs\
    $rust\
    $cmd_duration\
    $line_break\
    $character"""

    [character]
    success_symbol = "[>](bold green)"
    error_symbol = "[>](bold red)"

    [directory]
    truncation_length = 3
    truncate_to_repo = true

    [git_branch]
    symbol = "git:"

    [nix_shell]
    disabled = true

    [env_var.KONDUCTOR_SHELL]
    format = '[$symbol($env_value)]($style) '
    symbol = "❄️ "
    style = "bold blue"
  '';

  # Config file - written to nix store
  configFile = pkgs.writeTextFile {
    name = "konductor-starship-config";
    destination = "/starship.toml";
    text = configContent;
  };

in
{
  # Wrapped starship that forces hermetic config
  package = pkgs.writeShellApplication {
    name = "starship";
    runtimeInputs = [ pkgs.starship ];
    text = ''
      export STARSHIP_CONFIG="${configFile}/starship.toml"
      exec starship "$@"
    '';
  };

  unwrapped = pkgs.starship;

  # Config file
  inherit configFile;
  inherit configContent;

  # Metadata
  meta = {
    description = "Starship prompt with Konductor theme";
    configurable = true;
  };
}
