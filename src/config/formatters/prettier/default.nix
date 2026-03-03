# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier
#
# Config is maintained in native YAML format (.prettierrc.yaml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.
#
# Includes prettier-plugin-slidev for Slidev presentation markdown files.
# The plugin depends on @slidev/parser at runtime which must be available in
# the project's node_modules (true for any Slidev project by definition).

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "prettier-config";
    destination = "/.prettierrc.yaml";
    text = builtins.readFile ./.prettierrc.yaml;
  };

  # prettier-plugin-slidev: handles multi-frontmatter --- blocks in Slidev markdown
  # Without this, prettier treats mid-file --- as horizontal rules and destroys
  # frontmatter by collapsing YAML keys onto single lines.
  # https://github.com/slidevjs/prettier-plugin
  prettierPluginSlidev = pkgs.fetchurl {
    url = "https://registry.npmjs.org/prettier-plugin-slidev/-/prettier-plugin-slidev-1.0.5.tgz";
    hash = "sha256-+2ued/XCn58+kt+BgWwWYXB/FJBnEVW0rz9EUefGkes=";
  };

  # Unpack the plugin tarball into a usable directory
  pluginDir = pkgs.runCommand "prettier-plugin-slidev-1.0.5" {} ''
    mkdir -p $out
    tar xzf ${prettierPluginSlidev} -C $out --strip-components=1
  '';
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.nodePackages.prettier ];
    text = ''
      # NODE_PATH allows the plugin to resolve @slidev/parser from the project's node_modules
      _cwd="$(pwd)"
      NODE_PATH="''${NODE_PATH:+$NODE_PATH:}$_cwd/node_modules"
      export NODE_PATH
      exec prettier \
        --config "${configFile}/.prettierrc.yaml" \
        --plugin "${pluginDir}/dist/index.js" \
        "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.prettier;
  inherit configFile pluginDir;

  meta = {
    description = "Code formatter with Slidev plugin";
    configurable = true;
  };
}
