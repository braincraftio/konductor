# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier
#
# Config is maintained in native YAML format (.prettierrc.yaml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.
#
# TODO: Slidev plugin disabled — causes 120+ minute build regression
#
#   The prettier-plugin-slidev buildNpmPackage pulls a massive npm dependency tree
#   (@slidev/parser, @slidev/types, prettier, vite, hundreds of transitive deps)
#   which forces Node.js to build from source during QCOW2 image builds.
#   Build time went from ~43 minutes to ~163 minutes.
#
#   The upstream plugin (https://github.com/slidevjs/prettier-plugin) is unmaintained
#   (last release v1.0.5, ~2 years old). It handles multi-frontmatter --- blocks in
#   Slidev markdown files — without it, prettier treats mid-file --- as horizontal
#   rules and destroys frontmatter by collapsing YAML keys onto single lines.
#
#   Paths forward:
#   1. Fork slidevjs/prettier-plugin, maintain as braincraft package
#   2. Write a minimal replacement that only handles --- frontmatter preservation
#   3. Pre-build the plugin as a fixed derivation (fetchurl the npm tarball)
#   4. Vendor a pre-built dist/index.js directly in this repo (no buildNpmPackage)
#   5. Use a .prettierignore for slidev files and format them with a separate tool
#
#   The buildNpmPackage definition and package-lock.json are preserved below
#   for when we re-enable this.

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "prettier-config";
    destination = "/.prettierrc.yaml";
    text = builtins.readFile ./.prettierrc.yaml;
  };

  # DISABLED: prettier-plugin-slidev — see TODO above
  #
  # prettier-plugin-slidev: handles multi-frontmatter --- blocks in Slidev markdown.
  # Without this, prettier treats mid-file --- as horizontal rules and destroys
  # frontmatter by collapsing YAML keys onto single lines.
  # https://github.com/slidevjs/prettier-plugin
  #
  # Built from source so that buildNpmPackage vendors all dependencies
  # (including @slidev/parser and prettier) into node_modules/ adjacent
  # to the plugin's dist/index.js. ESM bare specifier resolution walks
  # node_modules/ relative to the importing file, so this layout lets
  # the plugin resolve its imports without NODE_PATH hacks.
  #
  # prettierPluginSlidev = pkgs.buildNpmPackage {
  #   pname = "prettier-plugin-slidev";
  #   version = "1.0.5";
  #
  #   src = pkgs.fetchFromGitHub {
  #     owner = "slidevjs";
  #     repo = "prettier-plugin";
  #     rev = "v1.0.5";
  #     hash = "sha256-AIlOwylRuZ6/I4whoc/dJdGRQoldWVzTucABsnCEREo=";
  #   };
  #
  #   npmDepsHash = "sha256-UaDGJPCFs0alYq9wOqkMtJZreQTFdhuIkF6pJaHb5x4=";
  #
  #   # The repo uses pnpm-lock.yaml but buildNpmPackage needs package-lock.json.
  #   # We supply a generated one.
  #   postPatch = ''
  #     cp ${./prettier-plugin-slidev.package-lock.json} package-lock.json
  #   '';
  #
  #   # Build produces dist/index.js via vite
  #   npmBuildScript = "build";
  #
  #   # Keep node_modules in the output so ESM can resolve @slidev/parser and prettier
  #   installPhase = ''
  #     runHook preInstall
  #     mkdir -p $out/lib/node_modules/prettier-plugin-slidev
  #     cp -r dist package.json node_modules $out/lib/node_modules/prettier-plugin-slidev/
  #     runHook postInstall
  #   '';
  #
  #   meta = {
  #     description = "Prettier plugin for Slidev multi-frontmatter markdown";
  #     homepage = "https://github.com/slidevjs/prettier-plugin";
  #     license = pkgs.lib.licenses.mit;
  #   };
  # };
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.prettier ];
    text = ''
      exec prettier \
        --config "${configFile}/.prettierrc.yaml" \
        "$@"
    '';
    # DISABLED: slidev plugin flag — re-enable when plugin is restored
    # text = ''
    #   exec prettier \
    #     --config "${configFile}/.prettierrc.yaml" \
    #     --plugin "${prettierPluginSlidev}/lib/node_modules/prettier-plugin-slidev/dist/index.js" \
    #     "$@"
    # '';
  };

  unwrapped = pkgs.prettier;
  inherit configFile;
  # DISABLED: re-enable when slidev plugin is restored
  # inherit configFile prettierPluginSlidev;

  meta = {
    description = "Code formatter";
    configurable = true;
  };
}
