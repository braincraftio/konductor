# src/config/linters/stylelint/default.nix
# Hermetic wrapper for stylelint
#
# Config is maintained in native JSON format (.stylelintrc.json) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.
#
# Delegated validation (not disabled checks):
#   at-rule-no-unknown ignoreAtRules = theme, plugin. These Tailwind v4
#   directives are validated by their owner, the Tailwind compiler
#   (@tailwindcss/vite in `astro build`), which fails the site build on an
#   unresolvable @plugin. That build gates pull requests in
#   .github/workflows/pages.yaml. Only at-rules in use are listed; every other
#   unknown at-rule (including misspellings) still fails stylelint.
#   import-notation = string: Tailwind's @import "tailwindcss" form.

{ pkgs, ... }:

let
  # Config file - native JSON, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "stylelint-config";
    destination = "/.stylelintrc.json";
    text = builtins.readFile ./.stylelintrc.json;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "stylelint";
    runtimeInputs = [ pkgs.stylelint ];
    text = ''
      # --allow-empty-input: an empty staged-file glob is a pass, not an error.
      exec stylelint --config "${configFile}/.stylelintrc.json" --allow-empty-input "$@"
    '';
  };

  unwrapped = pkgs.stylelint;
  inherit configFile;

  meta = {
    description = "CSS/SCSS linter";
    configurable = true;
  };
}
