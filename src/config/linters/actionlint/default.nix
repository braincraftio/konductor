# src/config/linters/actionlint/default.nix
# Hermetic wrapper for actionlint
#
# actionlint lints `run:` scripts with shellcheck and `shell: python` steps
# with pyflakes. The nixpkgs actionlint package prepends its own unwrapped
# shellcheck and a python3.14 pyflakes to PATH. The wrapper passes both
# executables explicitly so workflow scripts are checked by the konductor
# shellcheck (same .shellcheckrc as hooks and runme) and by pyflakes built on
# the pinned Python from src/lib/versions.nix.

{
  pkgs,
  versions,
  shellcheck,
}:

let
  pythonPackages = pkgs."python${versions.languages.python.version}Packages";
in
{
  package = pkgs.writeShellApplication {
    name = "actionlint";
    runtimeInputs = [ pkgs.actionlint ];
    text = ''
      exec actionlint \
        -shellcheck "${pkgs.lib.getExe shellcheck}" \
        -pyflakes "${pkgs.lib.getExe' pythonPackages.pyflakes "pyflakes"}" \
        "$@"
    '';
  };

  unwrapped = pkgs.actionlint;
  configFile = null; # repository config, if any, is .github/actionlint.yaml

  meta = {
    description = "GitHub Actions workflow linter";
    configurable = false;
  };
}
