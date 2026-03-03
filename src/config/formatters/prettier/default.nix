# src/config/formatters/prettier/default.nix
# Hermetic wrapper for prettier
#
# Config is maintained in native YAML format (.prettierrc.yaml) for easy contribution.
# The wrapper forces config via --config flag with no escape hatch.
#
# Includes prettier-plugin-slidev for Slidev presentation markdown files.
# The plugin is built from source via buildNpmPackage with @slidev/parser
# vendored in node_modules/ so ESM bare specifier resolution works.
# (ESM ignores NODE_PATH — it resolves relative to the importing file.)

{ pkgs, ... }:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "prettier-config";
    destination = "/.prettierrc.yaml";
    text = builtins.readFile ./.prettierrc.yaml;
  };

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
  prettierPluginSlidev = pkgs.buildNpmPackage {
    pname = "prettier-plugin-slidev";
    version = "1.0.5";

    src = pkgs.fetchFromGitHub {
      owner = "slidevjs";
      repo = "prettier-plugin";
      rev = "v1.0.5";
      hash = "sha256-AIlOwylRuZ6/I4whoc/dJdGRQoldWVzTucABsnCEREo=";
    };

    npmDepsHash = "sha256-UaDGJPCFs0alYq9wOqkMtJZreQTFdhuIkF6pJaHb5x4=";

    # The repo uses pnpm-lock.yaml but buildNpmPackage needs package-lock.json.
    # We supply a generated one.
    postPatch = ''
      cp ${./prettier-plugin-slidev.package-lock.json} package-lock.json
    '';

    # Build produces dist/index.js via vite
    npmBuildScript = "build";

    # Keep node_modules in the output so ESM can resolve @slidev/parser and prettier
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules/prettier-plugin-slidev
      cp -r dist package.json node_modules $out/lib/node_modules/prettier-plugin-slidev/
      runHook postInstall
    '';

    meta = {
      description = "Prettier plugin for Slidev multi-frontmatter markdown";
      homepage = "https://github.com/slidevjs/prettier-plugin";
      license = pkgs.lib.licenses.mit;
    };
  };
in
{
  package = pkgs.writeShellApplication {
    name = "prettier";
    runtimeInputs = [ pkgs.nodePackages.prettier ];
    text = ''
      exec prettier \
        --config "${configFile}/.prettierrc.yaml" \
        --plugin "${prettierPluginSlidev}/lib/node_modules/prettier-plugin-slidev/dist/index.js" \
        "$@"
    '';
  };

  unwrapped = pkgs.nodePackages.prettier;
  inherit configFile prettierPluginSlidev;

  meta = {
    description = "Code formatter with Slidev plugin";
    configurable = true;
  };
}
