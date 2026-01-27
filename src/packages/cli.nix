# src/packages/cli.nix
# Modern CLI tools - enhanced Unix utilities
#
# Shell tools (git, ssh) use hermetic wrappers from src/config/shell/
# when config is provided.

{
  pkgs,
  config ? null,
}:

let
  hasConfig = config != null;

  # Shell tools: wrapped when config available, unwrapped otherwise
  # All wrappers from src/config/shell/
  shellTools =
    if hasConfig then
      [
        config.shell.git.package # Git with forced Konductor gitconfig
        config.shell.ssh.package # SSH with KONDUCTOR_SSH_CONFIG support
        config.shell.starship.package # Starship with Konductor theme
        config.tree.package # Tree with gitignore-aware filtering
        # Note: bash.package is not included here - it's used via shellHook/bashrcContent
      ]
      ++ config.shell.atuin.packages # Atuin + bash-preexec for shell history
    else
      [
        pkgs.git
        pkgs.openssh
        pkgs.starship
        pkgs.tree
        pkgs.atuin
        pkgs.bash-preexec
      ];

  # System info tools: ff wrapper for hermetic fastfetch config
  systemInfoTools = if hasConfig then [ config.fastfetch.package ] else [ ];
in

{
  packages =
    shellTools
    ++ systemInfoTools
    ++ (with pkgs; [
      bash-completion # Bash programmable completion
      jq # JSON processor
      yq-go # YAML processor
      sqlite # SQLite for snacks.picker frecency
      gh # GitHub CLI
      tea # Gitea CLI
      forgejo-cli # Forgejo CLI
      gnugrep # GNU grep
      ripgrep # Fast grep (rg)
      fd # Fast find
      fzf # Fuzzy finder
      bottom # System monitor TUI (btm)
      fastfetch # System info display
      dnsutils # dig, nslookup, host
      ncdu # Disk usage analyzer
      watch # Run commands periodically
      file # File type detection
      # starship is in shellTools (wrapped)
      unstable.mise # Task runner and version manager
      direnv # Directory-based environments
      unstable.runme # Executable markdown documentation

      # Kubernetes tools (unstable for faster updates)
      unstable.kubectl # Kubernetes CLI
      unstable.kubecolor # Kubectl with color
      unstable.kubelogin-oidc # OIDC authentication for kubectl
      unstable.kubernetes-helm # Helm package manager
      unstable.k9s # Kubernetes TUI
      unstable.kubevirt # Includes virtctl for VM management
      unstable.hubble # Cilium network flow observability
      unstable.cilium-cli # Cilium CLI for network management

      # Talos/Omni tools (unstable for latest versions)
      unstable.talosctl # Talos Linux CLI (1.12.0)
      unstable.omnictl # Sidero Omni CLI (1.4.4)

      # Infrastructure as Code
      pulumi # IaC with real programming languages
      pulumictl # Pulumi CLI utilities
      pulumiPackages.pulumi-python # Python language plugin

      # Cloud provider CLIs (unstable for faster updates)
      unstable.awscli2 # AWS CLI v2
    ]);

  shellHook = "";
  env = if hasConfig then config.shell.bash.env // config.shell.atuin.env else { };
}
