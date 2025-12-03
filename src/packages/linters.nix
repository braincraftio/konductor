# src/packages/linters.nix
# Linting tools - composed from config wrappers

{ pkgs, config ? null }:

let
  # If config is provided, use wrapped versions; otherwise unwrapped
  hasConfig = config != null;
in

{
  packages =
    if hasConfig then [
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

      # Linters without config files
      pkgs.actionlint
      pkgs.statix
      pkgs.deadnix
    ] else with pkgs; [
      # Unwrapped linters for containers
      shellcheck
      ruff
      yamllint
      hadolint
      actionlint
      statix
      deadnix
    ];

  shellHook = "";
  env = { };
}
