# src/packages/network.nix
# Network and security packages

{ pkgs }:

{
  # Note: openssh is in cli.nix (wrapped with hermetic config)
  packages = with pkgs; [
    curl # HTTP client
    wget # HTTP/FTP retrieval
    gnupg # GPG for signing
    cacert # CA certificates
  ];

  shellHook = "";
  env = { };
}
