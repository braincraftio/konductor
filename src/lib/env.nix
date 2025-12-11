# src/lib/env.nix
# SSOT for ALL environment variables across ALL targets
# NO DUPLICATION - this is the ONLY place where env vars are defined
#
# NOTE: XDG Base Directory variables are NOT set here because they require
# shell expansion of $HOME. Setting them in Nix env creates literal "$HOME"
# directories. XDG vars are set in shellHook (devshells) and envExports
# (containers/VMs) where bash properly expands $HOME.

{
  # ===========================================================================
  # Editor Configuration
  # ===========================================================================
  EDITOR = "nvim";
  VISUAL = "nvim";
  PAGER = "bat";

  # ===========================================================================
  # Locale Configuration
  # ===========================================================================
  LANG = "C.UTF-8";
  LC_ALL = "C.UTF-8";

  # ===========================================================================
  # Terminal Configuration
  # ===========================================================================
  TERM = "xterm-256color";

  # ===========================================================================
  # SSL Certificate Configuration
  # ===========================================================================
  SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
  NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";

  # ===========================================================================
  # Konductor Marker
  # ===========================================================================
  KONDUCTOR = "true";

  # ===========================================================================
  # History Configuration
  # ===========================================================================
  HISTSIZE = "10000";
  HISTFILESIZE = "20000";
  HISTCONTROL = "ignoreboth:erasedups";
}
