# Contributing to Konductor

## Development Environment

```bash
git clone https://github.com/braincraftio/konductor.git
cd konductor
direnv allow
```

The devshell provides all tooling. Do not install tools via pip, npm, cargo, or brew.

## Commit Convention

Konductor uses [Conventional Commits](https://www.conventionalcommits.org/) enforced by commitlint
via lefthook pre-commit hooks.

```text
type(scope): description

[optional body]

[optional footer(s)]
```

Types and their release behavior:

| Type       | Release             | Description                                |
| ---------- | ------------------- | ------------------------------------------ |
| `feat`     | minor               | New feature                                |
| `fix`      | patch               | Bug fix                                    |
| `perf`     | patch               | Performance improvement                    |
| `revert`   | patch               | Revert previous commit                     |
| `docs`     | patch (README only) | Documentation                              |
| `refactor` | none                | Code restructuring without behavior change |
| `style`    | none                | Formatting, whitespace                     |
| `test`     | none                | Adding or updating tests                   |
| `build`    | none                | Build system or dependencies               |
| `ci`       | none                | CI/CD configuration                        |
| `chore`    | none                | Maintenance                                |

Breaking changes use `!` after the type: `feat(api)!: remove legacy endpoint`. This triggers a major
version bump.

Commit body is diff-derived, exhaustive, objective, present-tense. Enumerate every meaningful change
at the mechanism level. The bar is "a reader could reconstruct what changed and why from the body
alone."

No AI attribution. No PII. No `Co-Authored-By` with AI identity. No narrative or storytelling. No
past or future framing.

## Git Hooks

Lefthook (`lefthook.yml`) runs 19 parallel pre-commit jobs on the staged files of every
`git commit`:

| Job               | Files                                            | Tool                                   |
| ----------------- | ------------------------------------------------ | -------------------------------------- |
| `fmt`             | all staged files                                 | treefmt `--fail-on-change` (`nix fmt`) |
| `nix-lint`        | `*.nix`                                          | statix                                 |
| `nix-deadcode`    | `*.nix`                                          | deadnix                                |
| `python-lint`     | `*.py`                                           | ruff                                   |
| `python-types`    | `*.py`                                           | mypy                                   |
| `python-security` | `*.py`                                           | bandit                                 |
| `js-lint`         | `*.{js,jsx,ts,tsx,mjs,cjs,json,jsonc}`           | biome                                  |
| `shell-lint`      | `*.{sh,bash}`                                    | shellcheck                             |
| `yaml-lint`       | `*.{yml,yaml}`                                   | yamllint                               |
| `toml-lint`       | `*.toml`                                         | taplo                                  |
| `actions-lint`    | `.github/workflows/*.{yml,yaml}`                 | actionlint                             |
| `docker-lint`     | `**/Dockerfile*`                                 | hadolint                               |
| `go-lint`         | `*.go`                                           | golangci-lint                          |
| `html-lint`       | `*.html`                                         | htmlhint                               |
| `css-lint`        | `*.{css,scss,sass}`                              | stylelint                              |
| `markdown-lint`   | `*.{md,markdown}`                                | markdownlint-cli2                      |
| `spell-check`     | `*.{md,markdown,txt,js,jsx,ts,tsx,py,go,rs,nix}` | cspell                                 |
| `markdown-links`  | `*.{md,markdown}`                                | lychee (offline)                       |
| `secrets`         | all files except `.secrets.baseline`             | detect-secrets-hook `--no-verify`      |

Commit messages are validated by commitlint against the conventional commits spec.

Install hooks after cloning, then run every job over all tracked files (the same jobs, without
staging, failing on any change):

```bash
lefthook install
runme run hooks:run:all   # mise: mise run hooks:run:all (aliases hooks, hra)
```

All tools are provided by the konductor devshell. No manual installation required.

## Workflow

```bash
# Create feature branch
git checkout -b feat/my-improvement

# Make changes
# Hooks run automatically on commit

# Verify before push
nix flake check
runme run hooks:run:all
runme run lint
runme run fmt:check

# Commit (hooks validate automatically)
git commit -m "feat(scope): description"

# Push and open PR
git push origin feat/my-improvement
```

## CI Pipeline

Pushes and pull requests to `main` run `ci.yml`, which calls `nix.yml` on x86_64-linux,
aarch64-linux, and aarch64-darwin runners:

1. `nix flake show` and `nix flake check` (per-tool checks, treefmt, statix, deadnix)
2. Build the maintained packages and the k0sctl version test
3. `nix profile install .#default` (the consumer install path)
4. Build the default and full devshells, plus konductor and frontend on x86_64-linux

Pull request builds pull from Cachix and never push; push and release builds push to
`braincraftio.cachix.org`. A failed pull request build uploads `hash-repairs-<system>` patches for
`src/lib/versions.nix`. `.github/README.md` documents every workflow, including the weekly
`update.yml`.

## Release Process

`release.yml` runs after CI succeeds for a push to `main`, and only when `main` still matches the
tested revision:

1. semantic-release analyzes commits since the last tag
2. If releasable commits exist (`feat:`, `fix:`, `perf:`, `revert:`), a version is determined
3. `CHANGELOG.md` is updated and committed to main; the tag (e.g. `v1.2.3`) points at that commit
4. A GitHub Release is created with categorized release notes
5. The Nix Cache jobs build the release tag on all three platforms and push to Cachix
6. `publish-flake` publishes the tag to FlakeHub with its output paths

The tag includes the changelog commit, so the cached derivations match what consumers of the release
resolve.

No manual release steps. No version bumps in source. No changelog authoring. Conventional commits
determine everything.

## PR Checklist

Before opening a PR, verify:

- `nix flake check` passes
- `runme run hooks:run:all` passes
- `runme run lint` passes
- `runme run fmt:check` passes
- Single Source of Truth preserved (versions in `src/lib/versions.nix`)
- No duplicated logic across files
- Changes propagate to all relevant outputs (devshells, OCI, QCOW2, modules)
- Commit messages follow conventional commits format

## Version Updates

All pinned versions live in `src/lib/versions.nix`:

```nix
{
  languages = {
    python.version = "3.13";
    go.version = "1.27";
    node.version = "26";
    rust.version = "1.99.1";
  };
  atuin = { version = "18.24.1"; hash = "sha256-..."; cargoHash = "sha256-..."; };
}
```

Changing a version propagates to all devshells, containers, VMs, and modules.

Keep locally maintained versions and their source/dependency/platform hashes together in
`src/lib/versions.nix`. Overlays and packages consume these records:

- Atuin: `atuin.version`, `atuin.hash`, `atuin.cargoHash`
- k0sctl: `kubernetes.k0sctl.version`, `hash`, `vendorHash`
- Pulumi: CLI archive hashes, Python wheel URL/hash, and provider wheel/binary hashes alongside
  their respective versions
- Flake inputs: revisions and `narHash` remain together in `flake.lock`

Build affected packages after updating. Keep NixOS `stateVersion` unchanged during routine
dependency upgrades; it controls compatibility defaults.

## Workspace Setup with Open Sesame

[Open Sesame](https://github.com/ScopeCreep-zip/open-sesame) provides workspace management with
canonical directory paths, encrypted secret vaults, and SSH agent unlock. This is optional. Standard
`git clone` works without it.

```bash
# Clone to canonical workspace path
sesame workspace clone https://github.com/braincraftio/konductor

# Clone with profile linking for secret injection
sesame workspace clone https://github.com/braincraftio/konductor -p default

# Clone an entire org
sesame workspace clone https://github.com/braincraftio/konductor --project

# List all workspaces
sesame workspace list

# Check workspace status
sesame workspace status

# Open a shell with vault secrets injected
sesame workspace shell
```

The canonical path is `/workspace/<user>/<server>/<org>/<repo>`. Workspace-level `.envrc` files set
`WORKSPACE_ROOT` at the org namespace depth. Child repos inherit via `source_up_if_exists` with the
`_DIRENV_CHILD_SOURCING` guard.

Vault secrets are injected as environment variables via `sesame export -p default` in the `.envrc`.
This replaces plaintext tokens in `.env` files. The `.envrc` templates produced by
`nix flake init -t github:braincraftio/konductor` include Open Sesame vault injection blocks that
are no-ops when sesame is not installed.

## Architecture

See [CLAUDE.md](CLAUDE.md) for the maintainer operating model, dependency chain, overlay composition
order, and decision gates.

See [README.md](README.md) for the full flake output reference, shell specifications, and
user-facing documentation.
