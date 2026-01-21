# src/packages/network.nix
# Network and security packages

{ pkgs }:

{
  # Note: openssh is in cli.nix (wrapped with hermetic config)
  #
  # Netcat options in nixpkgs:
  #   netcat-openbsd - BROKEN: marked broken on Darwin/macOS in nixpkgs
  #   netcat-gnu     - BROKEN: -z flag returns exit 1 even on open ports (0.7.1)
  #   netcat         - alias to libressl-netcat, behaves like openbsd
  #
  packages = with pkgs; [
    curl # HTTP client
    wget # HTTP/FTP retrieval
    gnupg # GPG for signing
    cacert # CA certificates
    netcat
    # netcat-openbsd  # BROKEN: marked broken on Darwin/macOS in nixpkgs
    # netcat-gnu  # BROKEN: nc -zv returns exit 1 on open ports, unusable for scripting
  ];

  shellHook = "";
  env = { };
}
