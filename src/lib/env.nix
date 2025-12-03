# src/lib/env.nix
# SSOT for ALL environment variables across ALL targets
# NO DUPLICATION - this is the ONLY place where env vars are defined

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
  # XDG Base Directory Specification
  # ===========================================================================
  XDG_CONFIG_HOME = "$HOME/.config";
  XDG_CACHE_HOME = "$HOME/.cache";
  XDG_DATA_HOME = "$HOME/.local/share";
  XDG_STATE_HOME = "$HOME/.local/state";

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
