# src/packages/cli.nix
# Modern CLI tools - enhanced Unix utilities
#
# Shell tools (git, ssh) use hermetic wrappers from src/config/shell/
# when config is provided.

{ pkgs, config ? null }:

let
  hasConfig = config != null;

  # Shell tools: wrapped when config available, unwrapped otherwise
  # All wrappers from src/config/shell/
  shellTools =
    if hasConfig then [
      config.shell.git.package # Git with forced Konductor gitconfig
      config.shell.ssh.package # SSH with KONDUCTOR_SSH_CONFIG support
      config.shell.starship.package # Starship with Konductor theme
      # Note: bash.package is not included here - it's used via shellHook/bashrcContent
    ] else [
      pkgs.git
      pkgs.openssh
      pkgs.starship
    ];
in

{
  packages = shellTools ++ (with pkgs; [
    jq # JSON processor
    yq-go # YAML processor
    sqlite # SQLite for snacks.picker frecency
    gh # GitHub CLI
    ripgrep # Fast grep (rg)
    fd # Fast find
    fzf # Fuzzy finder
    # starship is in shellTools (wrapped)
    unstable.mise # Task runner and version manager
    direnv # Directory-based environments
    unstable.runme # Executable markdown documentation

    # Kubernetes tools
    kubectl # Kubernetes CLI
    kubelogin-oidc # OIDC authentication for kubectl
    k9s # Kubernetes TUI
    kubevirt # Includes virtctl for VM management

    # Infrastructure as Code
    pulumi # IaC with real programming languages
    pulumictl # Pulumi CLI utilities
    pulumiPackages.pulumi-python # Python language plugin
  ]);

  shellHook = "";
  env = { };
}
