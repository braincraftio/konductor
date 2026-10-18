# src/apps/update-prettier-astro-lock.nix
# Maintenance app: update prettier-plugin-astro and regenerate its vendored
# lockfile.
#
#   nix run .#update-prettier-astro-lock            # newest npm release
#   nix run .#update-prettier-astro-lock -- 0.15.0  # explicit version
#
# Steps (deterministic):
#   1. Fetch the published npm tarball for VERSION.
#   2. Apply the derivation's package.json transformation (drop
#      devDependencies and scripts).
#   3. npm install --package-lock-only → package-lock.json (lockfileVersion 3).
#   4. Write src/config/formatters/prettier/prettier-plugin-astro.package-lock.json.
#   5. Rewrite the prettier-plugin-astro record in src/lib/versions.nix:
#      version, hash (tarball SRI), npmDepsHash (prefetch-npm-deps over the
#      lock). Each previous value is replaced by exact string; a value that
#      does not occur exactly once stops the run before versions.nix is
#      written.

{ pkgs, versions }:

let
  record = versions.prettier-plugin-astro;
in
pkgs.writeShellApplication {
  name = "update-prettier-astro-lock";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.gnugrep
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.nix
    pkgs.nodejs
    pkgs.prefetch-npm-deps
  ];
  text = ''
    root=$(git rev-parse --show-toplevel)
    file="$root/src/lib/versions.nix"
    dest="$root/src/config/formatters/prettier/prettier-plugin-astro.package-lock.json"
    test -d "$(dirname "$dest")"

    version="''${1:-$(curl -fsSL https://registry.npmjs.org/prettier-plugin-astro/latest | jq -er .version)}"

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
    deps_hash=$(prefetch-npm-deps "$pkg/package-lock.json")

    replacements=(
      "${record.version}" "$version"
      "${record.hash}" "$tarball_hash"
      "${record.npmDepsHash}" "$deps_hash"
    )
    content=$(<"$file")
    for ((i = 0; i < ''${#replacements[@]}; i += 2)); do
      old="''${replacements[i]}" new="''${replacements[i + 1]}"
      [ "$old" = "$new" ] && continue
      count=$(grep -cF -- "\"$old\"" "$file" || true)
      if [ "$count" -ne 1 ]; then
        echo "error: \"$old\" occurs $count times in $file (expected 1)" >&2
        exit 1
      fi
      content=''${content/"\"$old\""/"\"$new\""}
    done

    cp "$pkg/package-lock.json" "$dest"
    printf '%s\n' "$content" > "$file"

    echo "prettier-plugin-astro ${record.version} -> $version"
    jq -r '.packages | to_entries[] | select(.key != "") | "  \(.key | sub("node_modules/"; "")) \(.value.version)"' "$dest"
  '';
  meta.description = "Update prettier-plugin-astro and its vendored lockfile and release hashes";
}
