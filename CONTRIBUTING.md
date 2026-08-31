# Contributing to Konductor

## Development Environment

```bash
git clone https://github.com/braincraftio/konductor.git
cd konductor
direnv allow
```

The devshell provides all tooling. Do not install tools via pip, npm, cargo, or brew.

## Commit Convention

Konductor uses [Conventional Commits](https://www.conventionalcommits.org/) enforced
by commitlint via lefthook pre-commit hooks.

```
type(scope): description

[optional body]

[optional footer(s)]
```

Types and their release behavior:

| Type | Release | Description |
|---|---|---|
| `feat` | minor | New feature |
| `fix` | patch | Bug fix |
| `perf` | patch | Performance improvement |
| `revert` | patch | Revert previous commit |
| `docs` | patch (README only) | Documentation |
| `refactor` | none | Code restructuring without behavior change |
| `style` | none | Formatting, whitespace |
| `test` | none | Adding or updating tests |
| `build` | none | Build system or dependencies |
| `ci` | none | CI/CD configuration |
| `chore` | none | Maintenance |

Breaking changes use `!` after the type: `feat(api)!: remove legacy endpoint`.
This triggers a major version bump.

Commit body is diff-derived, exhaustive, objective, present-tense. Enumerate every
meaningful change at the mechanism level. The bar is "a reader could reconstruct
what changed and why from the body alone."

No AI attribution. No PII. No `Co-Authored-By` with AI identity. No narrative or
storytelling. No past or future framing.

## Git Hooks

Lefthook runs 20+ parallel pre-commit checks automatically on `git commit`:

| Check | Files | Tool |
|---|---|---|
| Python style | `*.py` | ruff |
| Python types | `*.py` | mypy |
| Python security | `*.py` | bandit |
| JavaScript quality | `*.{js,jsx,ts,tsx}` | eslint |
| JavaScript style | `*.{js,jsx,ts,tsx}` | biome |
| Formatting | `*.{js,ts,json,css,html,md,yml}` | prettier |
| Shell syntax | `*.{sh,bash}` | shellcheck |
| YAML validation | `*.{yml,yaml}` | yamllint |
| TOML validation | `*.toml` | taplo |
| Nix formatting | `*.nix` | nixpkgs-fmt |
| Nix linting | `*.nix` | statix |
| Nix dead code | `*.nix` | deadnix |
| Markdown style | `*.{md,markdown}` | markdownlint-cli2 |
| Spelling | `*.{md,txt,js,ts,py,go,rs}` | cspell |
| Link validation | `*.{md,markdown}` | lychee (offline) |
| GitHub Actions | `.github/workflows/*.yml` | actionlint |
| Dockerfile | `Dockerfile*` | hadolint |
| Go | `*.go` | golangci-lint |
| HTML | `*.html` | htmlhint |
| CSS | `*.{css,scss,sass}` | stylelint |
| Secrets | all files | detect-secrets |

Commit messages are validated by commitlint against the conventional commits spec.

Install hooks after cloning:

```bash
lefthook install
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
runme run lint
runme run fmt:check

# Commit (hooks validate automatically)
git commit -m "feat(scope): description"

# Push and open PR
git push origin feat/my-improvement
```

## CI Pipeline

Pull requests trigger the CI workflow:

1. `nix flake check` runs all 9 checks (8 per-tool version checks + 1 buildEnv bundle integration check)
2. `nix build packages.default` verifies the installable buildEnv compiles
3. All built paths are pushed to `braincraftio.cachix.org` for binary cache warming

Fork PRs run checks but cannot push to cachix (org secrets are not available to forks).

## Release Process

Releases are fully automated via semantic-release on push to main:

1. semantic-release analyzes commits since the last tag
2. If releasable commits exist (`feat:`, `fix:`, `perf:`, `revert:`), a version is determined
3. A git tag is created (e.g. `v1.2.3`)
4. A GitHub Release is created with categorized release notes
5. `CHANGELOG.md` is updated and committed back to main
6. The nix-cache job builds from post-release main HEAD and pushes to cachix

The post-release cache build is critical for cache alignment. Consumers fetch
`github:braincraftio/konductor` which resolves to main HEAD (the post-changelog
commit). The nix-cache job builds from that same commit so derivation hashes match.
Builds from the tag would produce different hashes because the changelog commit
changes the flake's `self.narHash`.

No manual release steps. No version bumps in source. No changelog authoring.
Conventional commits determine everything.

## PR Checklist

Before opening a PR, verify:

- `nix flake check` passes (per-tool + bundle checks)
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
    python = { version = "313"; display = "3.13"; };
    go     = { version = "1_25"; display = "1.25"; };
    node   = { version = "22"; display = "22"; };
    rust   = { version = "1.98.0"; display = "1.98.0"; };
  };
  atuin = { version = "18.20.1"; display = "18.20.1"; };
}
```

Changing a version propagates to all devshells, containers, VMs, and modules.

For overlay-pinned packages (atuin, k0sctl), update hashes in the overlay file
alongside the version in `versions.nix`:

- Atuin: `src/overlays/atuin.nix` (src hash + cargoHash)
- k0sctl: `src/overlays/k0s.nix` (version + hashes)
- NixOS channel: `flake.nix` nixpkgs.url, nixvim.url, home-manager.url branches

## Workspace Setup with Open Sesame

[Open Sesame](https://github.com/ScopeCreep-zip/open-sesame) provides workspace
management with canonical directory paths, encrypted secret vaults, and SSH agent
unlock. This is optional. Standard `git clone` works without it.

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

The canonical path is `/workspace/<user>/<server>/<org>/<repo>`. Workspace-level
`.envrc` files set `WORKSPACE_ROOT` at the org namespace depth. Child repos inherit
via `source_up_if_exists` with the `_DIRENV_CHILD_SOURCING` guard.

Vault secrets are injected as environment variables via `sesame export -p default`
in the `.envrc`. This replaces plaintext tokens in `.env` files. The `.envrc`
templates produced by `nix flake init -t github:braincraftio/konductor` include
Open Sesame vault injection blocks that are no-ops when sesame is not installed.

## Architecture

See [CLAUDE.md](CLAUDE.md) for the maintainer operating model, dependency chain,
overlay composition order, and decision gates.

See [README.md](README.md) for the full flake output reference, shell specifications,
and user-facing documentation.
