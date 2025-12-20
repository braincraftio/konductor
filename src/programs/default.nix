# src/programs/default.nix
# Aggregates program exports
#
# Programs:
#   neovim  - NixVim-configured editor
#   tmux    - Terminal multiplexer with catppuccin
#   forgejo - Git forge tooling (server, runner, cli)

{ pkgs, lib, inputs }:

{
  neovim = import ./neovim { inherit pkgs lib inputs; };
  tmux = import ./tmux { inherit pkgs lib; };
  forgejo = import ./forgejo { inherit pkgs lib; };
}
