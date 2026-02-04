# src/modules/default.nix
# Module aggregation for NixOS, Home Manager, and nix-darwin

{
  nixos = import ./nixos.nix;
  homeManager = import ./home-manager.nix;
  darwin = import ./darwin.nix;

  # Konductor-specific modules
  pki = import ./pki.nix;           # VM identity and certificate chain of trust
  ttyd = import ./ttyd.nix;         # Web terminal (Catppuccin + Nerd Fonts)
  ghostty-web = import ./ghostty-web.nix;  # Experimental web terminal (gated)
}
