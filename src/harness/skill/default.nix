# Each immediate directory is one skill identity. Every directory must supply
# default.nix; there is no recursive discovery, implicit override, or merge order.
{ pkgs, lib }:
let
  directories = lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir ./.);
  definitions = lib.mapAttrs (id: _: import (./. + "/${id}") { inherit pkgs; }) directories;
in
import ./build.nix { inherit pkgs lib definitions; }
