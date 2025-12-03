# src/packages/network.nix
# Network and security packages

{ pkgs }:

{
  packages = with pkgs; [
    curl # HTTP client
    wget # HTTP/FTP retrieval
    openssh # SSH client
    gnupg # GPG for signing
    cacert # CA certificates
  ];

  shellHook = "";
  env = { };
}
