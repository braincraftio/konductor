# src/config/shell/starship.nix
# Starship prompt configuration

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

  configFile = pkgs.writeText "konductor-starship.toml" configContent;

in
{
  # Starship package
  package = pkgs.starship;
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
