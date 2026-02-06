# src/modules/default.nix
# Module aggregation for NixOS, Home Manager, and nix-darwin

{
  nixos = import ./nixos.nix;
  homeManager = import ./home-manager.nix;
  darwin = import ./darwin.nix;

  # Konductor-specific modules
  pki = import ./pki.nix;           # VM identity and certificate chain of trust

  # Web terminals (readonly and writable variants for enterprise access control)
  ttyd = import ./ttyd.nix;                   # ttyd readonly (port 7681)
  ttyd-rw = import ./ttyd-rw.nix;             # ttyd writable (port 7683)
  ghostty-web = import ./ghostty-web.nix;     # ghostty-web readonly (port 7682)
  ghostty-web-rw = import ./ghostty-web-rw.nix;  # ghostty-web writable (port 7684)
}
