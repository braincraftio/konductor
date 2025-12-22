# src/programs/neovim/banner.nix
# Konductor ASCII banners - SOURCE OF TRUTH for all branding
# Generated with: figlet -f banner3 KONDUCTOR
#
# Usage in plugins.nix: header = banner.fullWithTagline;
{ }:

rec {
  # Tagline - Cloud Developer Kit branding
  tagline = "Cloud Developer Kit";
  taglineShort = "Cloud Dev Kit";

  # Full banner (78 chars wide) - for terminals >= 80 columns
  full = ''
██╗  ██╗ ██████╗ ███╗   ██╗██████╗ ██╗   ██╗ ██████╗████████╗ ██████╗ ██████╗
██║ ██╔╝██╔═══██╗████╗  ██║██╔══██╗██║   ██║██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
█████╔╝ ██║   ██║██╔██╗ ██║██║  ██║██║   ██║██║        ██║   ██║   ██║██████╔╝
██╔═██╗ ██║   ██║██║╚██╗██║██║  ██║██║   ██║██║        ██║   ██║   ██║██╔══██╗
██║  ██╗╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝'';

  # Compact banner (40 chars wide) - for terminals 45-79 columns
  compact = ''
 █▄▀ █▀█ █▄ █ █▀▄ █ █ █▀▀ ▀█▀ █▀█ █▀█
 █ █ █▄█ █ ▀█ █▄▀ █▄█ █▄▄  █  █▄█ █▀▄'';

  # Minimal - for very narrow terminals
  minimal = "KONDUCTOR";

  # Pre-composed banners with taglines (use these in dashboard)
  fullWithTagline = ''
${full}
                         ${tagline}'';

  compactWithTagline = ''
${compact}
         ${taglineShort}'';

  minimalWithTagline = ''
${minimal}
${taglineShort}'';
}
