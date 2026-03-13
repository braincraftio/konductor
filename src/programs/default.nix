# src/programs/default.nix
# Aggregates program exports
#
# Programs:
#   neovim      - NixVim-configured editor
#   tmux        - Terminal multiplexer with catppuccin
#   forgejo     - Git forge tooling (server, runner, cli)
#   ttyd        - Web terminal with Catppuccin Frappé theme
#   ghostty-web - Browser-accessible terminal (experimental, requires feature flag)

{ pkgs
, lib
, inputs
,
}:

{
  neovim = import ./neovim { inherit pkgs lib inputs; };
  tmux = import ./tmux { inherit pkgs lib; };
  forgejo = import ./forgejo { inherit pkgs lib inputs; };
  ttyd = import ./ttyd { inherit pkgs lib; };
  ghostty-web = import ./ghostty-web { inherit pkgs lib; };
}
