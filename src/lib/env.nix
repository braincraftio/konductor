# src/lib/env.nix
# Centralized environment variables for all targets
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
  # LANG and LC_ALL are NOT set here. They were previously C.UTF-8 which
  # broke the COSMIC compositor — start-cosmic launches a login shell to
  # acquire user env vars, hm-session-vars.sh exported LANG=C.UTF-8, and
  # cosmic-comp's locale parser (icu4x) rejected it as an invalid BCP-47
  # language tag, causing all theme loading to fail (no transparency, no
  # frosted glass, hundreds of "error loading system theme" log entries).
  #
  # Desktop users inherit LANG from /etc/default/locale via PAM.
  # Containers set locale explicitly in OCI config (src/oci/default.nix).
  # Devshells inherit from the desktop session.

  # ===========================================================================
  # Terminal Configuration
  # ===========================================================================
  TERM = "xterm-256color";
  COLORTERM = "truecolor";

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
