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
  # NOTE: XDG vars are set in shellHook (base.nix) to properly expand $HOME
  # Do NOT set them here - Nix env attrs don't expand shell variables

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
