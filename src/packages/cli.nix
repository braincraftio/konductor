# src/packages/cli.nix
# Modern CLI tools - enhanced Unix utilities
#
# Shell tools (git, ssh, k9s) use hermetic wrappers from src/config/
# when config is provided.

{ pkgs
, config ? null
,
}:

let
  hasConfig = config != null;

  # Shell tools: wrapped when config available, unwrapped otherwise
  # All wrappers from src/config/
  shellTools =
    if hasConfig then
      [
        config.shell.git.package # Git with forced Konductor gitconfig
        config.shell.ssh.package # SSH with KONDUCTOR_SSH_CONFIG support
        config.shell.starship.package # Starship with Konductor theme
        config.tree.package # Tree with gitignore-aware filtering
        config.k9s.package # k9s with Catppuccin Frappe theme
        config.btop.package # btop with Catppuccin Frappe theme
        # Note: bash.package is not included here - it's used via shellHook/bashrcContent
      ]
      ++ config.shell.atuin.packages # Atuin + bash-preexec for shell history
    else
      [
        pkgs.git
        pkgs.openssh
        pkgs.starship
        pkgs.tree
        pkgs.unstable.k9s
        pkgs.btop
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
      yq-go # YAML/TOML processor
      yj # TOML/JSON/YAML converter
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
      # k9s: wrapped with Catppuccin theme in shellTools above
      unstable.kubevirt # Includes virtctl for VM management
      unstable.hubble # Cilium network flow observability
      unstable.cilium-cli # Cilium CLI for network management

      # Talos/Omni tools (unstable for latest versions)
      unstable.talosctl # Talos Linux CLI (1.12.0)
      unstable.omnictl # Sidero Omni CLI (1.4.4)

      # Infrastructure as Code
      # Pulumi with NixOS-native Python environment (src/packages/pulumi.nix)
      # Replaces: pulumi, pulumictl, pulumiPackages.pulumi-python
      # Provides python.withPackages environment with properly-linked native extensions
      (import ../packages/pulumi.nix { inherit pkgs; })

      # Cloud provider CLIs (unstable for faster updates)
      unstable.awscli2 # AWS CLI v2
    ]);

  shellHook = "";
  env = if hasConfig then config.shell.bash.env // config.shell.atuin.env else { };
}
