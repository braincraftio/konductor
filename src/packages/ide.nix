# src/packages/ide.nix
# IDE and developer experience tools

{ pkgs }:

{
  packages = with pkgs; [
    lazygit # Git TUI
    htop # Process monitor
    bottom # System monitor (btm)
    bat # cat with syntax highlighting
    eza # Modern ls
    dust # Disk usage analyzer
    tree # Directory tree
  ];

  shellHook = "";
  env = { };
}
