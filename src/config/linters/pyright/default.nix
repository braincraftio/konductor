# src/config/linters/pyright/default.nix
# Hermetic wrapper for pyright
#
# Injects --pythonpath pointing at the nix python.withPackages interpreter
# so pyright can introspect sys.path and resolve all installed packages.
# Without this, pyright's node.js binary cannot find nix-managed site-packages.
#
# lib.hiPrio: pythonEnv (python3.withPackages) also contains bin/pyright
# (via pulumi.nix pyrightPkg — required for Pulumi's typechecker subprocess).
# mkShell handles duplicate bin/ entries via PATH shadowing, but buildEnv
# (used by home-manager, nixos, nix-darwin modules) fails on collision.
# hiPrio gives this wrapper priority so buildEnv resolves the conflict.

{ pkgs, pythonEnv }:

{
  package = pkgs.lib.hiPrio (pkgs.writeShellApplication {
    name = "pyright";
    runtimeInputs = [ pkgs.pyright ];
    text = ''
      exec pyright --pythonpath "${pythonEnv}/bin/python3" "$@"
    '';
  });

  unwrapped = pkgs.pyright;

  meta = {
    description = "Python type checker with nix environment resolution";
    configurable = true;
  };
}
