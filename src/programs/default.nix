# src/programs/default.nix
# Aggregates program exports

{ pkgs, lib, inputs }:

{
  neovim = import ./neovim { inherit pkgs lib inputs; };
  tmux = import ./tmux { inherit pkgs lib; };
}
