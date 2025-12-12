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

    # Kubernetes tools
    kubectl # Kubernetes CLI
    kubelogin-oidc # OIDC authentication for kubectl
    k9s # Kubernetes TUI
    kubevirt # Includes virtctl for VM management

    # Infrastructure as Code
    pulumi # IaC with real programming languages
    pulumictl # Pulumi CLI utilities
    pulumiPackages.pulumi-language-python # Python language plugin
  ];

  shellHook = "";
  env = { };
}
