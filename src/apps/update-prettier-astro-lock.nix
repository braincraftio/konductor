# src/apps/update-prettier-astro-lock.nix
# Maintenance app: regenerate the vendored prettier-plugin-astro lockfile.
#
#   nix run .#update-prettier-astro-lock            # version from versions.nix
#   nix run .#update-prettier-astro-lock -- 0.15.0  # explicit version
#
# Steps (deterministic, no repository state besides the lockfile is written):
#   1. Fetch the published npm tarball for VERSION.
#   2. Apply the derivation's package.json transformation (drop
#      devDependencies and scripts).
#   3. npm install --package-lock-only → package-lock.json (lockfileVersion 3).
#   4. Write src/config/formatters/prettier/prettier-plugin-astro.package-lock.json.
#   5. Print the release record values for src/lib/versions.nix:
#      hash (tarball SRI) and npmDepsHash (prefetch-npm-deps over the lock).
#
# The record is printed rather than rewritten in place; versions.nix is
# hand-maintained Nix and is edited deliberately.

{ pkgs, versions }:

pkgs.writeShellApplication {
  name = "update-prettier-astro-lock";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.nix
    pkgs.nodejs
    pkgs.prefetch-npm-deps
  ];
  text = ''
    version="''${1:-${versions.prettier-plugin-astro.version}}"
    root=$(git rev-parse --show-toplevel)
    dest="$root/src/config/formatters/prettier/prettier-plugin-astro.package-lock.json"
    test -d "$(dirname "$dest")"

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    url="https://registry.npmjs.org/prettier-plugin-astro/-/prettier-plugin-astro-$version.tgz"
    echo "fetching $url"
    curl -fsSL -o "$work/pkg.tgz" "$url"
    tarball_hash=$(nix hash file --sri "$work/pkg.tgz")

    tar -xzf "$work/pkg.tgz" -C "$work"
    pkg="$work/package"
    test -f "$pkg/dist/index.js" || { echo "tarball has no dist/index.js" >&2; exit 1; }

    jq 'del(.devDependencies) | del(.scripts)' "$pkg/package.json" > "$pkg/package.json.tmp"
    mv "$pkg/package.json.tmp" "$pkg/package.json"

    npm install --prefix "$pkg" --package-lock-only --ignore-scripts --no-audit --no-fund
    cp "$pkg/package-lock.json" "$dest"
    deps_hash=$(prefetch-npm-deps "$dest")

    echo
    echo "wrote $dest"
    jq -r '.packages | to_entries[] | select(.key != "") | "  \(.key | sub("node_modules/"; "")) \(.value.version)"' "$dest"
    echo
    echo "src/lib/versions.nix prettier-plugin-astro:"
    echo "  version     = \"$version\";"
    echo "  hash        = \"$tarball_hash\";"
    echo "  npmDepsHash = \"$deps_hash\";"
  '';
  meta.description = "Regenerate the vendored prettier-plugin-astro lockfile and print its release hashes";
}
