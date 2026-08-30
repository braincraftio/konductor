# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Konductor is a Nix flake providing hermetic, multi-target polyglot development environments. It
delivers consistent tooling across devshells, OCI containers, QCOW2 VMs, and
NixOS/Darwin/Home-Manager modules using the Single Source of Truth pattern.

## Common Commands

### Enter Development Environment

```bash
nix develop              # Default shell, core tools, no languages
nix develop .#full       # All languages + IDE: Python, Go, Node, Rust, Neovim
nix develop .#konductor  # Full + docker/qemu/libvirt for self-hosting builds
nix develop .#python     # Python-specific
nix develop .#go         # Go-specific
nix develop .#node       # Node.js-specific
nix develop .#rust       # Rust-specific
nix develop .#dev        # IDE tools only: Neovim, tmux, lazygit
nix develop .#frontend   # Konductor + Playwright + Tauri
```

### Linting and Formatting

```bash
# Via runme, preferred, tasks defined in docs/developer_guide/LINT.md
runme run lint           # Run all linters
runme run fmt            # Format all files
runme run fmt:check      # Check formatting without changes

# Via mise
mise run lint            # Run all linters
mise run format          # Format all files

# Individual tools, all wrapped with hermetic configs
statix check .           # Nix linting
deadnix --fail .         # Dead Nix code detection
nixpkgs-fmt --check .    # Nix formatting check
shellcheck <file>        # Shell script linting
yamllint <file>          # YAML linting
```

### Flake Operations

```bash
nix flake check          # Validate flake, CI check
nix flake show           # Show outputs
nix flake update         # Update all inputs
nix build .#qcow2        # Build QCOW2 VM image, Linux only
nix build .#oci          # Build OCI container, Linux only
```

### QCOW2 VM Build, Linux, requires KVM

```bash
runme run build:qcow2:image    # Build QCOW2 image
runme run build:qcow2:start    # Start VM for development
runme run build:qcow2:stop     # Stop VM
runme run build:qcow2:publish  # Full pipeline: build, container, push
ssh localhost                  # SSH to VM, devshell configures port 2222
```

### Setup and Verification

```bash
runme run setup:verify   # Verify environment is configured correctly
mise run doctor          # Comprehensive health checks
```

## Architecture

### Data Flow

```
src/lib/versions.nix    SSOT: language versions, NixOS channel
    ↓
src/overlays/versions.nix    pkgs.konductor.* namespace
    ↓
src/packages/*.nix    category-based composition
    ↓
src/devshells/*.nix    base shell + language/IDE overrides
    ↓
flake.nix outputs    devShells, packages, modules
```

### Key Directories

- `src/lib/` SSOT data: versions.nix, users.nix, env.nix, theme.nix, aliases.nix
- `src/packages/` Package composition by category: core, cli, languages, linters, formatters, ai, ide
- `src/devshells/` Shell definitions using `overrideAttrs` pattern
- `src/config/` Hermetic linter/formatter configs, wrapped tools inject /nix/store paths
- `src/programs/` Neovim via nixvim, tmux, ttyd, ghostty-web, shell configurations
- `src/overlays/` Version pins for atuin and k0s, platform fixes for lld and direnv CGO, vim-plugins
- `src/oci/` nix2container OCI image definition
- `src/qcow2/` QCOW2 VM definition, native nixpkgs image building
- `src/modules/` NixOS, nix-darwin, home-manager modules
- `docs/developer_guide/` Runme task definitions in markdown

### Shell Hierarchy

```
base (default)
  ├── python    base + Python 3.13 + uv + ruff + mypy
  ├── go        base + Go 1.25 + gopls + delve
  ├── node      base + Node 22 + pnpm + biome
  ├── rust      base + Rust 1.98.0 + cargo + clippy
  ├── dev       base + neovim + tmux + IDE tools
  ├── full      all languages + dev
  ├── konductor full + docker + qemu + libvirt, x86_64-linux
  └── frontend  konductor + Playwright + Tauri, x86_64-linux
```

### Dependency Chain

```
nixpkgs fork    usrbinkat/nixpkgs gssproxy-package-and-module, based on nixos-26.05
  ↑ consumed by
flake.nix    nixpkgs.url
  ↑ consumed by
home-manager flake    konductor.url = github:braincraftio/konductor
```

### Flake Source Metadata

`self.shortRev` is threaded from `flake.nix` through `sourceInfo` to
`devshells/default.nix` to `konductor.nix` and displayed in the devshell banner.
When the tree has uncommitted changes, shortRev is "dirty". `self.rev`,
`self.lastModifiedDate`, and `self.narHash` are also available in `sourceInfo`
for derivations that need build provenance.

## Version Updates

All versions are centralized in `src/lib/versions.nix`. When updating:

1. Edit `src/lib/versions.nix` for language versions and atuin version
2. For NixOS channel changes, also update `flake.nix` nixpkgs.url, nixvim.url,
   and home-manager.url branches
3. For atuin bumps, update src hash + cargoHash in `src/overlays/atuin.nix`
4. For k0sctl bumps, update version + hashes in `src/overlays/k0s.nix`

### Overlay-Pinned Packages

These packages are pinned ahead of nixpkgs via overlays in `src/overlays/`:

- **atuin** tip-of-spear to prevent SQLite migration skew across consumers.
  Built with rust-overlay toolchain because nixos-26.05 rustc is behind atuin MSRV.
  Bump: `versions.nix` + `atuin.nix` src hash and cargoHash
- **k0sctl** ahead of both nixpkgs channels. Bump: `versions.nix` + `k0s.nix`

### nixpkgs Fork Maintenance

The flake consumes `github:usrbinkat/nixpkgs/gssproxy-package-and-module`, a fork of
nixos-26.05 carrying: maintainer entry, gssproxy package + NixOS module + VM test,
lesscpy version bump, freeipa pkg_resources + patchShebangs fix. When upstream merges
these, switch to `github:NixOS/nixpkgs/nixos-26.05`.

## Commit Convention

Uses Conventional Commits enforced by commitlint via lefthook pre-commit hooks. Format:

```
type(scope): description

Types: feat, fix, docs, style, refactor, perf, test, chore
```

Commit body is diff-derived, exhaustive, objective, present-tense. Enumerate every
meaningful change at the mechanism level. The bar is "a reader could reconstruct what
changed and why from the body alone."

## Git Hooks

Lefthook runs 20+ parallel pre-commit checks automatically:

- Nix: statix, deadnix, nixpkgs-fmt
- Python: ruff, mypy, bandit
- JS/TS: eslint, biome, prettier
- Shell: shellcheck
- Config: yamllint, taplo
- Docs: markdownlint, cspell, lychee
- Docker: hadolint
- Go: golangci-lint
- Security: detect-secrets

## MCP Servers

Configured in `.mcp.json`:

- `deepwiki` repository documentation, HTTP transport, mcp.deepwiki.com
- `nixos` NixOS package/option search, stdio, mcp-nixos binary from nixpkgs

## Environment Variables

Loaded via direnv from `.env.docker-dev.example` for defaults and `.env` for local overrides:

- `GITHUB_TOKEN` GitHub authentication via `gh auth token`, used by gh CLI
- `GITEA_TOKEN` Gitea/Forgejo authentication
- `CONTAINER_REGISTRY` container registry, default registry.braincraft.io
- `CONTAINER_IMAGE` image name, default containercraft/konductor

## Maintainer Operating Model

### Observation completeness

Every action's quality is bounded by the quality of its input observation. Command output,
file contents, diffs, and commit logs are read in full before any decision that depends on
them. Summarized, filtered, or truncated observations produce decisions that are correct for
the summary and wrong for the reality.

Git log format is `--format=fuller`. Diffs are full. `--stat` is supplementary, not
sufficient. Command output flows unfiltered. No `| head`, `| tail`, `| grep` before the
output has been read. The file or output is the source of truth, not the expectation.

### State verification before state mutation

Operations that change shared state require explicit enumeration of what exists on both
sides of the change before execution. Remote branches, published packages, and applied
system configurations are shared state. Enumerate what the operation will create, modify,
and destroy. Confirm the destroyed set contains nothing unrecoverable. The verification
and the mutation are separate steps with a human-readable boundary between them.

For git: `git -C <path>`, not `cd`. The staged diff is the deliverable. Read the full
staged diff before commit. Read the full divergence before push. Before rebase, reset,
or force push: read both sides of the divergence with `--format=fuller`, identify
cherry-pick equivalents, confirm the destroyed set contains nothing unique. Lock files
are generated from resolved source, not copied from either side of a conflict.

### Dependency currency

When a dependency version gap, missing tool, or deprecation warning surfaces, the response
is to update to current, not to work around the version constraint. "The version isn't up
to date" is not a separate concern from version maintenance. What version does upstream
ship? What version do we run? The delta is the work.

Every tool required to maintain the flake belongs in the devshell. If a maintenance
operation fails because a tool is missing from PATH, the devshell is incomplete.

### Convention propagation

Every change in the codebase either matches the established conventions or migrates all
instances to a better convention. Introducing a second form for the same operation creates
an implicit fork. `--replace` alongside existing `--replace-fail`, or `stdenv.isDarwin`
alongside existing `stdenv.hostPlatform.isDarwin`, produces two forms. The next contributor
reads both, cannot determine the intent difference, and propagates the weaker form.

Comments describe operational context for the next maintainer's decision, not history.
"Tracks main; CI-tested per commit" helps someone decide whether to pin or follow HEAD.
"Moved to nix-community" is a `git log` entry.

### Root cause ownership

Workarounds are legitimate as triage under time pressure, tracked as debt, and resolved
before the next maintenance cycle completes. A workaround that outlives the availability
of its root cause fix is a defect. `enableNixpkgsReleaseCheck = false` existed because
the fork was master-based. When the fork rebased onto nixos-26.05, the workaround was
removed in the same commit.

### Decision gates

At every step before execution:

1. **Information completeness** Can the decision be wrong because of something unread?
   Read it. The file, the output, the diff, the upstream API.

2. **Mutation safety** Does this operation change shared state? Verify the full input
   state. Read both sides of the divergence. Confirm nothing unique is lost.

3. **Convention match** Does this change introduce a form that differs from the
   established form for the same operation? Match it, or migrate all instances.

4. **Toolchain completeness** Can the next maintainer complete this task with only
   what's in the repo? Add what's missing.

5. **Workaround currency** Is there a carried workaround whose root cause is now
   fixable? Fix the root cause. Remove the workaround.

These gates hold regardless of what upstream ships. The outcome that must hold after
every maintenance action: all versions verified against upstream, updated to current,
all deprecation warnings and evaluation traces resolved, all workarounds whose root
cause has been addressed eliminated, build and eval confirmed before push.

### Scope and acceptance criteria

Scope is determined by acceptance criteria derived from forcing functions, not by
operator preference or agent opinion. Neither party exempts work by categorizing it
out of scope. Work is in scope when the forcing functions require it.

Identifying a gap and then categorizing the project to exempt it from the principle
is eliminating work by reclassification. The correct process: do the forcing functions
require this discipline? `nix flake check` is a test. NixOS VM tests are tests.
Build-and-eval verification is a test. If the forcing functions require them to go
red before green, the principle applies because the criteria require it.

Correct diagnosis followed by invented justification for inaction is the same
structural pattern regardless of surface content. Apply acceptance criteria before
presenting options. If a candidate fails any forcing function, it is eliminated,
not discussed.

Concluding "no enhancement needed" before the evaluation is complete inverts the
evidence. Present findings, then conclude. A conclusion that precedes its evidence
is an assertion, not an analysis.
