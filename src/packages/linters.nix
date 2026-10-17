# src/packages/linters.nix
# Linting tools - composed from config wrappers

{
  pkgs,
  lib,
  config ? null,
}:

let
  # If config is provided, use wrapped versions; otherwise unwrapped
  hasConfig = config != null;
in

{
  packages =
    if hasConfig then
      [
        # Wrapped linters
        config.linters.shellcheck.package
        config.linters.ruff.package
        config.linters.yamllint.package
        config.linters.hadolint.package
        config.linters.eslint.package
        config.linters.golangci-lint.package
        config.linters.mypy.package
        config.linters.bandit.package
        config.linters.markdownlint.package
        config.linters.commitlint.package
        (lib.hiPrio config.linters.pyright.package)
        config.linters.deadnix.package # targets: tracked *.nix, or after --
        config.linters.statix.package
        config.linters.actionlint.package # konductor shellcheck + pinned pyflakes
        config.linters.cspell.package
        config.linters.lychee.package
        config.linters.stylelint.package
        config.linters.htmlhint.package

        # Linters without config files
        pkgs.detect-secrets # detect-secrets-hook gates; detect-secrets scan/audit maintain the baseline

        # Git hooks: lefthook owns .git/hooks in this repository.
        # pre-commit and prek are shipped for consuming projects and are never
        # installed here (all three write the same .git/hooks/<type> shims).
        pkgs.lefthook
        pkgs.pre-commit
        pkgs.prek
      ]
    else
      # ERROR: config must be provided for wrapped linters
      # Unwrapped linters violate hermetic configuration standards
      throw "linters.nix requires config parameter - unwrapped linters are not permitted";

  shellHook = "";
  env = { };
}
