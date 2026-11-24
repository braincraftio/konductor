# src/config/linters/stylelint/default.nix
# Hermetic wrapper for stylelint
#
# Config is maintained in native JSON format (.stylelintrc.json) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.
#
# Shareable configs: .stylelintrc.json extends stylelint-config-standard,
# which extends stylelint-config-recommended. stylelint resolves a bare
# `extends` name from --config-basedir first, then the working directory, then
# global node_modules (lib/utils/getModulePath.mjs). The config directory
# carries both packages in node_modules at the versions in src/lib/versions.nix
# (stylelint-config), so resolution always ends in the store and never in a
# node_modules above the checked files.
#
# Delegated validation (not disabled checks):
#   at-rule-no-unknown ignoreAtRules = theme, plugin. These Tailwind v4
#   directives are validated by their owner, the Tailwind compiler
#   (@tailwindcss/vite in `astro build`), which fails the site build on an
#   unresolvable @plugin. That build gates pull requests in
#   .github/workflows/pages.yaml. Only at-rules in use are listed; every other
#   unknown at-rule (including misspellings) still fails stylelint.
#   import-notation = string: Tailwind's @import "tailwindcss" form.

{ pkgs, versions }:

let
  release = versions.stylelint-config;
  tarball =
    name: record:
    pkgs.fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${name}-${record.version}.tgz";
      inherit (record) hash;
    };

  configDir = pkgs.runCommand "stylelint-config" { } ''
    mkdir -p $out/node_modules/stylelint-config-standard $out/node_modules/stylelint-config-recommended
    tar -xzf ${tarball "stylelint-config-standard" release.standard} \
      -C $out/node_modules/stylelint-config-standard --strip-components=1
    tar -xzf ${tarball "stylelint-config-recommended" release.recommended} \
      -C $out/node_modules/stylelint-config-recommended --strip-components=1
    cp ${./.stylelintrc.json} $out/.stylelintrc.json
  '';
in
{
  package = pkgs.writeShellApplication {
    name = "stylelint";
    runtimeInputs = [ pkgs.stylelint ];
    text = ''
      # --allow-empty-input: an empty staged-file glob is a pass, not an error.
      exec stylelint --config "${configDir}/.stylelintrc.json" \
        --config-basedir "${configDir}" --allow-empty-input "$@"
    '';
  };

  unwrapped = pkgs.stylelint;
  configFile = configDir;

  meta = {
    description = "CSS/SCSS linter";
    configurable = true;
  };
}
