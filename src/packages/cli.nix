# src/packages/cli.nix
# Modern CLI tools - enhanced Unix utilities

{ pkgs }:

{
  packages = with pkgs; [
    git # Version control
    jq # JSON processor
    yq-go # YAML processor
    gh # GitHub CLI
    ripgrep # Fast grep (rg)
    fd # Fast find
    fzf # Fuzzy finder
    starship # Cross-shell prompt
    unstable.mise # Task runner and version manager
    direnv # Directory-based environments
  ];

  shellHook = "";
  env = { };
}
