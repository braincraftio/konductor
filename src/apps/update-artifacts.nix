# src/apps/update-artifacts.nix
# Maintenance app: update release records in src/lib/versions.nix whose
# artifacts are fetched by URL (prebuilt per-platform tarballs, PyPI wheels)
# and so cannot be refreshed by nix-update from a single host.
#
#   nix run .#update-artifacts
#
# Records and sources:
#   terminal-browser.version, hashes.<system>
#                                newest `v<semver>` release of
#                                zenbu-labs/terminal-browser; one tarball per system
#   pulumi.version, url, hash    newest `pulumi` wheel on PyPI
#   pulumi.cliHashes.<system>    GitHub release tarball of the same version
#                                (the CLI language host and SDK must match)
#   pulumi.providers.<name>.*    newest `pulumi_<name>` wheel on PyPI, and the
#                                pulumi-resource-<name> plugin tarball of that
#                                version per system
#   pyright.version, url, hash   newest `pyright` wheel on PyPI
#
# Wheel URLs are PyPI's content-addressed paths with SHA-256 from the PyPI
# JSON API. Tarball hashes come from nix-prefetch-url, so every platform is
# computed from one host. Each previous value (read from the evaluated
# versions record) is replaced by exact string; a value that does not occur
# exactly once in versions.nix stops the run before anything is written.
# GITHUB_TOKEN, when set, authenticates api.github.com requests only.

{ pkgs, versions }:

let
  current = (pkgs.formats.json { }).generate "versions.json" versions;
in
pkgs.writeShellApplication {
  name = "update-artifacts";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.nix
  ];
  text = ''
    root=$(git rev-parse --show-toplevel)
    file="$root/src/lib/versions.nix"
    current=${current}

    old() { jq -er "$1" "$current"; }

    # Stage every replacement first; write only after all values resolve.
    replacements=()
    stage() {
      if [ -z "$1" ] || [ -z "$2" ]; then
        echo "error: empty value in replacement '$1' -> '$2'" >&2
        exit 1
      fi
      if [ "$1" != "$2" ]; then
        local count
        count=$(grep -cF -- "\"$1\"" "$file" || true)
        if [ "$count" -ne 1 ]; then
          echo "error: \"$1\" occurs $count times in $file (expected 1)" >&2
          exit 1
        fi
        replacements+=("$1" "$2")
      fi
    }

    github_api() {
      local auth=()
      if [ -n "''${GITHUB_TOKEN:-}" ]; then
        auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
      fi
      curl -fsSL "''${auth[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
    }
    # Newest release whose tag is exactly v<major>.<minor>.<patch>.
    github_latest_semver() {
      github_api "repos/$1/releases?per_page=100" \
        | jq -r '.[] | select(.draft | not) | select(.prerelease | not) | .tag_name' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n 1 \
        | grep .
    }
    pypi_latest() { curl -fsSL "https://pypi.org/pypi/$1/json" | jq -er '.info.version'; }
    pypi_wheel() {
      curl -fsSL "https://pypi.org/pypi/$1/$2/json" | jq -er '
        [.urls[] | select(.packagetype == "bdist_wheel")]
        | if length == 1 then .[0] | "\(.url) \(.digests.sha256)"
          else error("expected exactly one wheel, found \(length)") end'
    }
    sri() { nix hash convert --hash-algo sha256 --to sri "$1"; }
    prefetch() { sri "$(nix-prefetch-url --type sha256 "$1")"; }

    # Runs in the calling shell (never inside $(...)) so its staged
    # replacements persist; the resolved version is left in wheel_version.
    wheel_version=""
    wheel_record() {
      local path=$1 pypi=$2 url sha
      wheel_version=$(pypi_latest "$pypi")
      read -r url sha < <(pypi_wheel "$pypi" "$wheel_version")
      echo "$pypi $(old "$path.version") -> $wheel_version" >&2
      stage "$(old "$path.version")" "$wheel_version"
      stage "$(old "$path.url")" "$url"
      stage "$(old "$path.hash")" "$(sri "$sha")"
    }

    # terminal-browser (matches src/overlays/terminal-browser.nix)
    declare -A tb_artifact=(
      [x86_64-linux]=linux-x64 [aarch64-linux]=linux-arm64
      [aarch64-darwin]=darwin-arm64 [x86_64-darwin]=darwin-x64
    )
    tb_version=$(github_latest_semver zenbu-labs/terminal-browser)
    echo "terminal-browser $(old '."terminal-browser".version') -> $tb_version" >&2
    stage "$(old '."terminal-browser".version')" "$tb_version"
    for system in "''${!tb_artifact[@]}"; do
      stage "$(old ".\"terminal-browser\".hashes.\"$system\"")" "$(prefetch "https://github.com/zenbu-labs/terminal-browser/releases/download/v$tb_version/terminal-browser-''${tb_artifact[$system]}.tar.gz")"
    done

    # pulumi (matches src/packages/pulumi.nix)
    declare -A os=([x86_64-linux]=linux [aarch64-linux]=linux [aarch64-darwin]=darwin)
    declare -A cli_arch=([x86_64-linux]=x64 [aarch64-linux]=arm64 [aarch64-darwin]=arm64)
    declare -A plugin_arch=([x86_64-linux]=amd64 [aarch64-linux]=arm64 [aarch64-darwin]=arm64)
    systems=(x86_64-linux aarch64-linux aarch64-darwin)

    wheel_record .pulumi pulumi
    pulumi_version=$wheel_version
    for system in "''${systems[@]}"; do
      stage "$(old ".pulumi.cliHashes.\"$system\"")" "$(prefetch "https://github.com/pulumi/pulumi/releases/download/v$pulumi_version/pulumi-v$pulumi_version-''${os[$system]}-''${cli_arch[$system]}.tar.gz")"
    done

    mapfile -t providers < <(jq -r '.pulumi.providers | keys[]' "$current")
    for name in "''${providers[@]}"; do
      wheel_record ".pulumi.providers.\"$name\"" "pulumi_''${name//-/_}"
      version=$wheel_version
      for system in "''${systems[@]}"; do
        stage "$(old ".pulumi.providers.\"$name\".pluginHashes.\"$system\"")" "$(prefetch "https://github.com/pulumi/pulumi-$name/releases/download/v$version/pulumi-resource-$name-v$version-''${os[$system]}-''${plugin_arch[$system]}.tar.gz")"
      done
    done

    # pyright (src/packages/pulumi.nix)
    wheel_record .pyright pyright

    content=$(<"$file")
    for ((i = 0; i < ''${#replacements[@]}; i += 2)); do
      content=''${content/"\"''${replacements[i]}\""/"\"''${replacements[i + 1]}\""}
    done
    printf '%s\n' "$content" > "$file"

    echo "$(( ''${#replacements[@]} / 2 )) values updated in $file"
  '';
  meta.description = "Update URL-fetched release records (terminal-browser, pulumi, pyright) in src/lib/versions.nix";
}
