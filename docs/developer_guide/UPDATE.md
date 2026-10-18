---
cwd: ../..
shell: bash
skipPrompts: true
tag: target:update,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor Version Maintenance

Update flake inputs and locally maintained release records, recomputing every source and dependency
hash.

## Contents

- [Quick Start](#quick-start)
- [Update Tasks](#update-tasks)

---

## Quick Start

| Task              | Description                                                        |
| ----------------- | ------------------------------------------------------------------ |
| `update`          | Update flake inputs, then every release record                     |
| `update:inputs`   | `nix flake update`: every input revision and narHash in flake.lock |
| `update:releases` | `nix-update` every release record in `src/lib/versions.nix`, build |

Release records live in `src/lib/versions.nix`; the derivations that consume them live in
`src/overlays/` and `src/packages/`. `nix-update --flake <attr>` evaluates
`packages.<system>.<attr>`, finds the newest upstream release, and with
`--override-filename src/lib/versions.nix` rewrites the version, the source hash, and the dependency
hash (`cargoHash`, `vendorHash`) in that file, then builds the package. A record already at the
newest release is left unchanged after its hashes are recomputed and verified.

---

## Update Tasks

### `update`

Update flake inputs, then every release record. Review `git diff` and run `nix flake check` before
committing.

```sh {"name":"update","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
runme run update:inputs
runme run update:releases
git --no-pager diff --stat -- flake.lock src/lib/versions.nix
```

`runme run update`

---

### `update:inputs`

Update every flake input revision and narHash in `flake.lock`.

```sh {"name":"update:inputs","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
nix flake update
```

`runme run update:inputs`

---

### `update:releases`

Update each source-built release record with nix-update and build it. `flakehub-push` tracks
upstream `main` by revision (`--version=branch`); after it changes, set the
`DeterminateSystems/flakehub-push` SHA in `.github/actions/publish-flake/action.yml` to the new
`flakehub-push.rev`. Records fetched by URL (per-platform terminal-browser and pulumi tarballs, PyPI
wheels) are refreshed by `nix run .#update-artifacts`, which prefetches every platform's artifact
from one host; prettier-plugin-astro by `nix run .#update-prettier-astro-lock`. Every updater runs;
the task fails if any failed.

```sh {"name":"update:releases","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
FAILED=()
update() {
    echo "=== $* ==="
    if ! nix-update --flake --override-filename src/lib/versions.nix --build "$@"; then
        FAILED+=("$*")
    fi
    echo ""
}

update atuin
update k0sctl
update trzsz
update flakehub-push --version=branch
update code-server --system x86_64-linux

echo "=== URL-fetched artifacts (terminal-browser, pulumi, pyright) ==="
if ! nix run .#update-artifacts; then
    FAILED+=("update-artifacts")
fi
echo ""

echo "=== prettier-plugin-astro ==="
if ! nix run .#update-prettier-astro-lock; then
    FAILED+=("update-prettier-astro-lock")
fi
echo ""

if [ "${#FAILED[@]}" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAILED[@]}"
    exit 1
fi
echo "All release records updated"
```

`runme run update:releases`
