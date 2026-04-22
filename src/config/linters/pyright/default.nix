# src/config/linters/pyright/default.nix
# Hermetic wrapper for pyright
#
# Injects --pythonpath pointing at the nix python.withPackages interpreter
# so pyright can introspect sys.path and resolve all installed packages.
# Without this, pyright's node.js binary cannot find nix-managed site-packages.

{ pkgs, pythonEnv }:

{
  package = pkgs.writeShellApplication {
    name = "pyright";
    runtimeInputs = [ pkgs.pyright ];
    text = ''
      exec pyright --pythonpath "${pythonEnv}/bin/python3" "$@"
    '';
  };

  unwrapped = pkgs.pyright;

  meta = {
    description = "Python type checker with nix environment resolution";
    configurable = true;
  };
}
