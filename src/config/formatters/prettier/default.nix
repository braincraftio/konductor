# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier
#
# Config is maintained in native YAML format (.prettierrc.yaml) for easy contribution.
# The wrapper forces config via --config and loads the packaged Astro plugin,
# so *.astro files are formatted by the same binary hooks, runme, and CI use.
#
# prettier-plugin-slidev (multi-frontmatter Slidev markdown) is not loaded: its
# buildNpmPackage closure regressed QCOW2 build time from ~43 to ~163 minutes.
# prettier-plugin-slidev.package-lock.json is retained for a fixed-output
# rebuild of that plugin.

{ pkgs, versions }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "prettier-config";
    destination = "/.prettierrc.yaml";
    text = builtins.readFile ./.prettierrc.yaml;
  };

  astroPlugin = import ./astro-plugin.nix { inherit pkgs versions; };
  astroPluginEntry = "${astroPlugin}/lib/node_modules/prettier-plugin-astro/dist/index.js";
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.prettier ];
    text = ''
      exec prettier \
        --config "${configFile}/.prettierrc.yaml" \
        --plugin "${astroPluginEntry}" \
        "$@"
    '';
  };

  unwrapped = pkgs.prettier;
  inherit configFile astroPlugin;

  meta = {
    description = "Code formatter (markdown, yaml, html, css, astro)";
    configurable = true;
  };
}
