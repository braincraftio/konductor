# src/packages/formatters.nix
# Formatting tools - composed from config wrappers
#
# Python formatting is ruff (`ruff check --select I --fix`, then `ruff format`,
# ordered by treefmt priorities); black and isort are not shipped.

{
  config ? null,
  pkgs,
  ...
}:

let
  hasConfig = config != null;
in

{
  packages =
    if hasConfig then
      [
        # Single entrypoint: treefmt bound to every formatter below (nix fmt)
        config.formatters.treefmt.package

        # Wrapped formatters (per-file use: editors, hooks, explicit invocation)
        config.formatters.shfmt.package
        config.formatters.prettier.package
        config.formatters.taplo.package
        config.formatters.biome.package
        config.formatters.nixfmt.package

        # Formatters without config files
        pkgs.gofumpt
        pkgs.stylua
      ]
    else
      # ERROR: config must be provided for wrapped formatters
      # Unwrapped formatters violate hermetic configuration standards
      throw "formatters.nix requires config parameter - unwrapped formatters are not permitted";

  shellHook = "";
  env = { };
}
