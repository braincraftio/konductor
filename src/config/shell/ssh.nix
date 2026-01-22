# src/config/shell/ssh.nix
# Hermetic SSH config for Konductor VM access
#
# Design rationale (informed by OpenSSH documentation):
# - SSH config precedence: 1) command-line, 2) ~/.ssh/config, 3) /etc/ssh/ssh_config
# - First match wins within each config file
# - Include directive in ~/.ssh/config can pull in additional configs
#
# Solution:
# - Provide a static config file in the nix store for localhost VM access
# - Users add "Include /nix/store/.../konductor-ssh.conf" to their ~/.ssh/config
# - No wrappers, no -F flag, no interference with user's SSH setup
# - shellHook exports KONDUCTOR_SSH_CONFIG path for easy reference
# - Completely hermetic: zero writes to ~/.ssh/
#
# Exports:
#   package    - Unwrapped openssh (no wrapper needed)
#   configFile - Static SSH config in nix store for localhost VM
#   shellHook  - Exports KONDUCTOR_SSH_CONFIG and KONDUCTOR_SSH_PUBKEY
#   env        - Environment variables

{ pkgs, ... }:

let
  # Static SSH config for Konductor VM access (lives in /nix/store)
  # Users include this in their ~/.ssh/config:
  #   Include /nix/store/.../konductor-ssh.conf
  # Or reference via: Include ${KONDUCTOR_SSH_CONFIG}
  sshConfigFile = pkgs.writeText "konductor-ssh.conf" ''
    # Konductor VM SSH Configuration
    # Include this in your ~/.ssh/config:
    #   Include ''${KONDUCTOR_SSH_CONFIG}
    #
    # This provides localhost:2222 access to Konductor VMs

    Host localhost
        HostName localhost
        Port 2222
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        LogLevel ERROR
        ConnectTimeout 5
  '';

  # Shell hook to detect SSH identity (dynamic, needs $HOME)
  # KONDUCTOR_SSH_CONFIG is set via env attribute (static nix path)
  shellHookScript = ''
    # Detect SSH identity for cloud-init and automation (needs $HOME at runtime)
    if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
      KONDUCTOR_SSH_PUBKEY="$HOME/.ssh/id_ed25519.pub"
    elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
      KONDUCTOR_SSH_PUBKEY="$HOME/.ssh/id_rsa.pub"
    fi
  '';

in
{
  # No wrapper - use openssh directly
  # User's ~/.ssh/config works normally
  package = pkgs.openssh;

  unwrapped = pkgs.openssh;

  # Static config file in nix store
  configFile = sshConfigFile;

  # ShellHook exports config path and identity
  shellHook = shellHookScript;

  # Environment variables for devshells
  env = {
    KONDUCTOR_SSH_CONFIG = "${sshConfigFile}";
  };

  # Export the config path
  configPath = "${sshConfigFile}";

  meta = {
    description = "SSH config for Konductor VM access";
    configurable = true;
    envVar = "KONDUCTOR_SSH_CONFIG";
  };
}
