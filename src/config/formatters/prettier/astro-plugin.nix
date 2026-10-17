# src/config/formatters/prettier/astro-plugin.nix
# prettier-plugin-astro, loaded by the prettier wrapper with --plugin.
#
# nixpkgs (locked rev) provides no prettier Astro plugin and prettier exposes
# no withPlugins interface, so the plugin is packaged here.
#
# Source: the published npm tarball, which ships the built dist/index.js.
# Upstream's pnpm-lock.yaml (lockfileVersion 6.0) is rejected by every pnpm in
# nixpkgs (pnpm 10/11/12; 8 and 9 are removed), so the production dependency
# tree is pinned by a vendored package-lock.json instead.
#
# Release record: src/lib/versions.nix prettier-plugin-astro
#   hash         SRI of the npm tarball
#   npmDepsHash  fetchNpmDeps output for the vendored lockfile
# Maintenance: nix run .#update-prettier-astro-lock [-- VERSION]
#   regenerates prettier-plugin-astro.package-lock.json and prints both hashes.
#
# Single prettier instance: the plugin's own node_modules/prettier is replaced
# with the nixpkgs prettier the wrapper executes, so the plugin's
# `import "prettier"` resolves to the running formatter, not a second copy.

{ pkgs, versions }:

let
  inherit (pkgs) lib;
  release = versions.prettier-plugin-astro;
in
pkgs.buildNpmPackage {
  pname = "prettier-plugin-astro";
  inherit (release) version npmDepsHash;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/prettier-plugin-astro/-/prettier-plugin-astro-${release.version}.tgz";
    inherit (release) hash;
  };
  sourceRoot = "package";

  # Same transformation update-prettier-astro-lock applies before locking:
  # production dependencies only, no lifecycle scripts.
  postPatch = ''
    ${lib.getExe pkgs.jq} 'del(.devDependencies) | del(.scripts)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./prettier-plugin-astro.package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  postInstall = ''
    plugin="$out/lib/node_modules/prettier-plugin-astro"
    test -f "$plugin/dist/index.js"
    rm -rf "$plugin/node_modules/prettier"
    ln -s ${pkgs.prettier}/lib/node_modules/prettier "$plugin/node_modules/prettier"
  '';

  passthru.pluginPath = "lib/node_modules/prettier-plugin-astro/dist/index.js";

  meta = {
    description = "Prettier plugin for Astro components";
    homepage = "https://github.com/withastro/prettier-plugin-astro";
    license = lib.licenses.mit;
  };
}
