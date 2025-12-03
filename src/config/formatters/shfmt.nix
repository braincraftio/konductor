# src/config/formatters/shfmt.nix
# Hermetic wrapper for shfmt with standard flags

{ pkgs }:

{
  package = pkgs.writeShellApplication {
    name = "shfmt";
    runtimeInputs = [ pkgs.shfmt ];
    text = ''
      exec shfmt -i 4 -ci -sr -kp -bn "$@"
    '';
  };

  unwrapped = pkgs.shfmt;
  configFile = null; # No config file, uses flags

  meta = {
    description = "Shell script formatter with standard flags";
    configurable = false;
  };
}
