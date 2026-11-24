---
cwd: ../..
shell: bash --noprofile --norc
skipPrompts: true
tag: target:lint,target:fmt,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor Lint & Format

Code quality tools for linting and formatting.

## Contents

- [Quick Start](#quick-start)
- [Lint Tasks](#lint-tasks)
- [Fix Tasks](#fix-tasks)
- [Secrets Tasks](#secrets-tasks)
- [Hook Tasks](#hook-tasks)
- [Format Tasks](#format-tasks)

---

## Quick Start

| Task                      | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| `lint`                    | Run all linters                                      |
| `lint:nix`                | Lint Nix (statix, deadnix)                           |
| `lint:python`             | Lint Python (ruff, mypy, bandit)                     |
| `lint:js`                 | Lint JS/TS/JSON (biome)                              |
| `lint:bash`               | Lint shell scripts (shellcheck)                      |
| `lint:yaml`               | Lint YAML (yamllint)                                 |
| `lint:toml`               | Lint TOML (taplo)                                    |
| `lint:actions`            | Lint GitHub Actions (actionlint)                     |
| `lint:docker`             | Lint Dockerfiles (hadolint)                          |
| `lint:docs`               | Lint Markdown (markdownlint-cli2, lychee offline)    |
| `lint:links`              | Check Markdown links online (lychee, cached)         |
| `lint:commits`            | Lint commit messages in `COMMIT_FROM..COMMIT_TO`     |
| `lint:spell`              | Spell check (cspell)                                 |
| `lint:spell:words`        | List words missing from the project dictionary       |
| `lint:secrets`            | Scan for secrets against `.secrets.baseline`         |
| `fix:nix`                 | Apply statix and deadnix autofixes                   |
| `secrets:baseline:update` | Rescan and update `.secrets.baseline`                |
| `secrets:audit`           | Review `.secrets.baseline` findings interactively    |
| `hooks:check`             | Validate lefthook.yml and verify hooks are installed |
| `hooks:run:all`           | Run every pre-commit job over all tracked files      |
| `ci:gates`                | Hooks, commit range, and online links (CI entry)     |
| `fmt`                     | Format all files (`nix fmt`)                         |
| `fmt:check`               | Check formatting without changes (`checks.treefmt`)  |

All tasks call the konductor-wrapped, store-pinned tools that lefthook and `nix flake check` use,
and operate on git-tracked files. Gitignored trees such as `_sources/` (vendored nixpkgs and
rust-overlay checkouts) are never linted or formatted. Formatting has one owner, treefmt
(`nix fmt`); lint tasks never rewrite files.

---

## Lint Tasks

### `lint`

Run all linters. Every linter runs; the task fails if any failed.

```sh {"name":"lint","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
FAILED=()
for task in nix python js bash yaml toml actions docker docs spell secrets; do
    echo "=== lint:$task ==="
    if ! runme run "lint:$task"; then
        FAILED+=("lint:$task")
    fi
    echo ""
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed: ${FAILED[*]}"
    exit 1
fi
echo "All linters passed"
```

`runme run lint`

---

### `lint:nix`

Lint with statix and detect dead code with deadnix. Formatting is checked by `fmt:check`. statix
reads `.gitignore` and the wrapped `statix.toml`; the konductor `deadnix` wrapper targets
git-tracked `*.nix` files when no `--` is given. Same gates as `checks.statix` and `checks.deadnix`.

```sh {"name":"lint:nix","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
statix check
deadnix --fail
echo "Nix lint passed"
```

`runme run lint:nix`

---

### `lint:python`

Lint Python with ruff, type-check with mypy, security-scan with bandit.

```sh {"name":"lint:python","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.py')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No Python files"
    exit 0
fi
ruff check "${FILES[@]}"
mypy "${FILES[@]}"
bandit "${FILES[@]}"
echo "Python lint passed"
```

`runme run lint:python`

---

### `lint:js`

Lint JavaScript, TypeScript, and JSON with biome.

```sh {"name":"lint:js","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.js' '*.jsx' '*.ts' '*.tsx' '*.mjs' '*.cjs' '*.json' '*.jsonc')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No JS/TS/JSON files"
    exit 0
fi
biome lint --no-errors-on-unmatched "${FILES[@]}"
echo "JS lint passed"
```

`runme run lint:js`

---

### `lint:bash`

Lint shell scripts with shellcheck. The wrapper passes `--external-sources`. Discovery uses
`shfmt -f`, which selects tracked files that are shell by extension or shebang, so extensionless
scripts are included.

```sh {"name":"lint:bash","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z | xargs -0 --no-run-if-empty shfmt -f=0)
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No shell files"
    exit 0
fi
echo "Checking: ${#FILES[@]} files"
shellcheck "${FILES[@]}"
echo "Shell lint passed"
```

`runme run lint:bash`

---

### `lint:yaml`

Lint YAML with yamllint (`--strict`: warnings fail).

```sh {"name":"lint:yaml","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.yml' '*.yaml')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No YAML files"
    exit 0
fi
yamllint "${FILES[@]}"
echo "YAML lint passed"
```

`runme run lint:yaml`

---

### `lint:toml`

Lint TOML with taplo.

```sh {"name":"lint:toml","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.toml')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No TOML files"
    exit 0
fi
taplo lint "${FILES[@]}"
echo "TOML lint passed"
```

`runme run lint:toml`

---

### `lint:actions`

Lint GitHub Actions workflows with actionlint. The wrapper checks `run:` scripts with the konductor
shellcheck and `shell: python` steps with pyflakes on the pinned Python.

```sh {"name":"lint:actions","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No workflows"
    exit 0
fi
actionlint "${FILES[@]}"
echo "Actions lint passed"
```

`runme run lint:actions`

---

### `lint:docker`

Lint Dockerfiles with hadolint (failure threshold: info).

```sh {"name":"lint:docker","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- 'Dockerfile*' '**/Dockerfile*')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No Dockerfiles"
    exit 0
fi
hadolint "${FILES[@]}"
echo "Docker lint passed"
```

`runme run lint:docker`

---

### `lint:docs`

Lint Markdown with markdownlint-cli2 and check links offline with lychee.

```sh {"name":"lint:docs","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.md' '*.markdown')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No Markdown files"
    exit 0
fi
markdownlint-cli2 "${FILES[@]}"
lychee --offline --no-progress "${FILES[@]}"
echo "Docs lint passed"
```

`runme run lint:docs`

---

### `lint:links`

Check every link in tracked Markdown online with lychee. Results are cached in `.lycheecache`
(gitignored, `max_cache_age` in the wrapped `lychee.toml`); CI restores that file between runs.
`CHANGELOG.md` is excluded: semantic-release generates it from released commit messages.

```sh {"name":"lint:links","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
mapfile -d '' FILES < <(git ls-files -z -- '*.md' '*.markdown' ':!CHANGELOG.md')
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No Markdown files"
    exit 0
fi
lychee --no-progress "${FILES[@]}"
echo "Link check passed"
```

`runme run lint:links`

---

### `lint:commits`

Lint every commit message in a range with commitlint `--strict` (warnings fail). The range comes
from exactly one source:

- `COMMIT_FROM` and `COMMIT_TO`, set by the caller (local use).
- The GitHub Actions event (`GITHUB_EVENT_NAME`, `GITHUB_EVENT_PATH`) when neither is set:
  - `pull_request`: the merge-base of the base and head SHAs to the head SHA;
  - `push`: `before` to `after`, or, for a new ref (`before` all zeros), the merge-base with
    `origin/main` to `after`, which is the pushed commit alone when the ref is `main`;
  - `workflow_dispatch`: the merge-base with `origin/main` to `GITHUB_SHA`.

Any other event, or `COMMIT_*` set together with a GitHub event, is an error. Both endpoints must
exist locally (fetch full history) and the start must be an ancestor of the end. Equal endpoints
lint that single commit.

```sh {"name":"lint:commits","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
if [ -n "${GITHUB_EVENT_NAME:-}" ]; then
    if [ -n "${COMMIT_FROM:-}${COMMIT_TO:-}" ]; then
        echo "Set COMMIT_FROM/COMMIT_TO or run under a GitHub event, not both" >&2
        exit 1
    fi
    event() { jq -er "$1" "$GITHUB_EVENT_PATH"; }
    case "$GITHUB_EVENT_NAME" in
        pull_request)
            # base.sha is the base branch tip at event time; once that branch
            # moves past the PR's branch point it is not an ancestor of head.
            COMMIT_TO=$(event .pull_request.head.sha)
            COMMIT_FROM=$(git merge-base "$(event .pull_request.base.sha)" "$COMMIT_TO")
            ;;
        push)
            COMMIT_TO=$(event .after)
            before=$(event .before)
            if [[ "$before" =~ ^0+$ ]]; then
                COMMIT_FROM=$(git merge-base origin/main "$COMMIT_TO")
            else
                COMMIT_FROM=$before
            fi
            ;;
        workflow_dispatch)
            COMMIT_TO=$GITHUB_SHA
            COMMIT_FROM=$(git merge-base origin/main "$COMMIT_TO")
            ;;
        *)
            echo "No commit range for event ${GITHUB_EVENT_NAME}; valid: pull_request, push, workflow_dispatch" >&2
            exit 1
            ;;
    esac
fi
: "${COMMIT_FROM:?set COMMIT_FROM and COMMIT_TO, or run under a GitHub event}"
: "${COMMIT_TO:?set COMMIT_FROM and COMMIT_TO, or run under a GitHub event}"
echo "Linting ${COMMIT_FROM}..${COMMIT_TO}"
for rev in "$COMMIT_FROM" "$COMMIT_TO"; do
    if ! git cat-file -e "${rev}^{commit}"; then
        echo "Commit ${rev} is not available; fetch full history" >&2
        exit 1
    fi
done
if [ "$(git rev-parse "$COMMIT_FROM")" = "$(git rev-parse "$COMMIT_TO")" ]; then
    git log -1 --format=%B "$COMMIT_TO" | commitlint --strict
elif git merge-base --is-ancestor "$COMMIT_FROM" "$COMMIT_TO"; then
    commitlint --strict --from "$COMMIT_FROM" --to "$COMMIT_TO"
else
    echo "${COMMIT_FROM} is not an ancestor of ${COMMIT_TO}" >&2
    exit 1
fi
echo "Commit messages passed"
```

`COMMIT_FROM=origin/main COMMIT_TO=HEAD runme run lint:commits`

---

### `lint:spell`

Spell check tracked source and documentation with cspell. The wrapper loads
`src/config/linters/cspell/cspell.json` and `project-words.txt`.

```sh {"name":"lint:spell","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
git ls-files -- '*.md' '*.markdown' '*.txt' '*.js' '*.jsx' '*.ts' '*.tsx' '*.py' '*.go' '*.rs' '*.nix' \
    | cspell lint --no-progress --no-must-find-files --file-list stdin
echo "Spell check passed"
```

`runme run lint:spell`

---

### `lint:spell:words`

List every unknown word in tracked files, sorted and unique, one per line. Review the list; real
words for this project belong in `src/config/linters/cspell/project-words.txt`, misspellings get
fixed at the source. Nothing is written.

```sh {"name":"lint:spell:words","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail
git ls-files -- '*.md' '*.markdown' '*.txt' '*.js' '*.jsx' '*.ts' '*.tsx' '*.py' '*.go' '*.rs' '*.nix' \
    | cspell lint --no-progress --no-summary --no-must-find-files --no-exit-code \
        --words-only --unique --file-list stdin \
    | sort -fu
```

`runme run lint:spell:words`

---

### `lint:secrets`

Scan every tracked file with detect-secrets-hook against `.secrets.baseline`, the same gate as the
lefthook `secrets` job. Fails on any finding not in the baseline.

`--no-verify` keeps detection and disables only vendor liveness checks. With verification on, a
finding the vendor reports invalid (a revoked key) is filtered out and never fails the gate, every
candidate is sent to that vendor's API (AWS, Stripe, Slack, Mailchimp, Telegram, IBM, Cloudant,
SoftLayer), and a network error changes the result. `--no-verify` reports every candidate, offline
and deterministic. The lefthook job, this task, and `secrets:baseline:update` use the same mode, so
the baseline filter set is stable across them.

```sh {"name":"lint:secrets","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
git ls-files -z -- ':!.secrets.baseline' | xargs -0 --no-run-if-empty detect-secrets-hook --no-verify --baseline .secrets.baseline
echo "Secrets scan passed"
```

`runme run lint:secrets`

---

## Fix Tasks

### `fix:nix`

Apply statix autofixes and remove dead code with deadnix. Review the diff before staging.

```sh {"name":"fix:nix","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail
statix fix
deadnix --edit
git --no-pager diff --stat -- '*.nix'
```

`runme run fix:nix`

---

## Secrets Tasks

### `secrets:baseline:update`

Rescan tracked files and update `.secrets.baseline` in place. Plugin and filter settings (including
the SRI checksum exclusion) are read from the existing baseline; the scan runs `--no-verify`, the
same mode as `lint:secrets`. A scan with no finding changes leaves the file byte-identical. New
entries are unaudited: run `secrets:audit` before committing the updated baseline. CI never
regenerates the baseline.

```sh {"name":"secrets:baseline:update","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail
previous="$(mktemp)"
trap 'rm -f "$previous"' EXIT
cp .secrets.baseline "$previous"
detect-secrets scan --no-verify --baseline .secrets.baseline
# The scan rewrites generated_at on every run; keep the previous file when
# nothing else changed so an unchanged scan leaves no diff.
if [ "$(jq -S 'del(.generated_at)' "$previous")" = "$(jq -S 'del(.generated_at)' .secrets.baseline)" ]; then
    cp "$previous" .secrets.baseline
    echo "Baseline unchanged"
fi
git --no-pager diff -- .secrets.baseline
```

`runme run secrets:baseline:update`

---

### `secrets:audit`

Interactively label each baseline finding as a real secret or a false positive.

```sh {"name":"secrets:audit","excludeFromRunAll":"true","interactive":"true","tag":"type:entry"}
detect-secrets audit .secrets.baseline
```

`runme run secrets:audit`

---

## Hook Tasks

lefthook owns `.git/hooks` in this repository. Install once with `lefthook install`; bypass for a
single commit with `LEFTHOOK=0 git commit`. Run a tagged subset with
`lefthook run pre-commit --no-auto-install --tag nix`.

### `hooks:check`

Validate `lefthook.yml` and verify the hooks are installed.

```sh {"name":"hooks:check","excludeFromRunAll":"true","tag":"type:entry,scope:dev"}
set -euo pipefail
lefthook validate
lefthook check-install
echo "Hooks valid and installed"
```

`runme run hooks:check`

---

### `hooks:run:all`

Run every pre-commit job over all tracked files without installing hooks. Fails if any job fails or
changes a file.

```sh {"name":"hooks:run:all","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
lefthook validate
lefthook run pre-commit --all-files --no-auto-install --no-stage-fixed --fail-on-changes
```

`runme run hooks:run:all`

---

### `ci:gates`

The repository gates CI runs: every pre-commit job over tracked files, commit messages in the
event's range, and links online. Every gate runs; the task fails if any failed. Locally, set
`COMMIT_FROM` and `COMMIT_TO` for the commit gate.

```sh {"name":"ci:gates","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
FAILED=()
for task in hooks:run:all lint:commits lint:links; do
    echo "=== ${task} ==="
    if ! runme run "$task"; then
        FAILED+=("$task")
    fi
    echo ""
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed: ${FAILED[*]}"
    exit 1
fi
echo "All CI gates passed"
```

`COMMIT_FROM=origin/main COMMIT_TO=HEAD runme run ci:gates`

---

## Format Tasks

### `fmt`

Format all tracked files. `nix fmt` runs the flake `formatter` output: treefmt bound to every
konductor formatter (nixfmt, ruff, biome, prettier with the Astro plugin, shfmt, taplo, gofumpt,
stylua).

```sh {"name":"fmt","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail
nix fmt
```

`runme run fmt`

---

### `fmt:check`

Check formatting without modifying the working tree. Builds `checks.treefmt`, which runs
`treefmt --ci` on a sandbox copy of the flake source, the same gate `nix flake check` runs.

```sh {"name":"fmt:check","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -euo pipefail
system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build --no-link -L ".#checks.${system}.treefmt"
echo "All files formatted correctly"
```

`runme run fmt:check`
