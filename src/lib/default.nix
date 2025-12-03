# src/lib/default.nix
# Aggregates all lib exports

{ lib }:

let
  versions = import ./versions.nix;
  users = import ./users.nix;
  env = import ./env.nix;
  aliases = import ./aliases.nix;
  shellContent = import ./shell-content.nix { inherit lib; };
  meta = import ./meta.nix { inherit versions; };
  utils = import ./utils.nix { inherit lib; };
in

{
  inherit versions users env aliases shellContent meta utils;
}
