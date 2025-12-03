# src/packages/ai.nix
# AI coding assistants and tools

{ pkgs }:

{
  packages = with pkgs; [
    unstable.claude-code
  ];

  shellHook = "";
  env = { };
}
