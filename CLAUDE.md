# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Konductor is a Nix flake providing hermetic, multi-target polyglot development environments. It delivers consistent tooling across devshells, OCI containers, QCOW2 VMs, and NixOS/Darwin/Home-Manager modules using the Single Source of Truth (SSOT) pattern.

## Common Commands

### Enter Development Environment
```bash
nix develop              # Default shell (core tools, no languages)
nix develop .#full       # All languages + IDE (Python, Go, Node, Rust, Neovim)
nix develop .#konductor  # Full + docker/qemu/libvirt for self-hosting builds
nix develop .#python     # Python-specific
nix develop .#go         # Go-specific
nix develop .#node       # Node.js-specific
nix develop .#rust       # Rust-specific
nix develop .#dev        # IDE tools only (Neovim, tmux, lazygit)
nix develop .#ci         # CI/CD runner environment
```

### Linting and Formatting
```bash
# Via runme (preferred - tasks defined in docs/developer_guide/LINT.md)
runme run lint           # Run all linters
runme run fmt            # Format all files
runme run fmt:check      # Check formatting without changes

# Via mise
mise run lint            # Run all linters
mise run format          # Format all files

# Individual tools (all wrapped with hermetic configs)
statix check .           # Nix linting
deadnix --fail .         # Dead Nix code detection
nixpkgs-fmt --check .    # Nix formatting check
shellcheck <file>        # Shell script linting
yamllint <file>          # YAML linting
```

### Flake Operations
```bash
nix flake check          # Validate flake (CI check)
nix flake show           # Show outputs
nix flake update         # Update all inputs
nix build .#qcow2        # Build QCOW2 VM image (Linux only)
nix build .#oci          # Build OCI container (Linux only)
```

### QCOW2 VM Build (Linux, requires KVM)
```bash
runme run build:qcow2:image    # Build QCOW2 image
runme run build:qcow2:start    # Start VM for development
runme run build:qcow2:stop     # Stop VM
runme run build:qcow2:publish  # Full pipeline: build → container → push
ssh localhost                  # SSH to VM (devshell configures port 2222)
```

### Setup and Verification
```bash
runme run setup:verify   # Verify environment is configured correctly
mise run doctor          # Comprehensive health checks
```

## Architecture

### Data Flow
```
src/lib/versions.nix (SSOT: language versions, NixOS channel)
    ↓
src/overlays/versions.nix (pkgs.konductor.* namespace)
    ↓
src/packages/*.nix (category-based composition)
    ↓
src/devshells/*.nix (base shell + language/IDE overrides)
    ↓
flake.nix outputs (devShells, packages, modules)
```

### Key Directories
- `src/lib/` - SSOT data: versions.nix, users.nix, env.nix, aliases.nix
- `src/packages/` - Package composition by category (core, cli, languages, linters, formatters, ai, ide)
- `src/devshells/` - Shell definitions using `overrideAttrs` pattern
- `src/config/` - Hermetic linter/formatter configs (wrapped tools inject /nix/store paths)
- `src/programs/` - Neovim (nixvim), tmux, shell configurations
- `src/oci/` - nix2container OCI image definition
- `src/qcow2/` - nixos-generators QCOW2 VM definition
- `src/modules/` - NixOS, nix-darwin, home-manager modules
- `docs/developer_guide/` - Runme task definitions in markdown

### Shell Hierarchy
```
base (default)
  ├── python (base + Python 3.13 + uv + ruff + mypy)
  ├── go (base + Go 1.24 + gopls + delve)
  ├── node (base + Node 22 + pnpm + biome)
  ├── rust (base + Rust 1.92.0 + cargo + clippy)
  ├── dev (base + neovim + tmux + IDE tools)
  ├── full (all languages + dev)
  ├── konductor (full + docker + qemu + libvirt)
  └── ci (full + forgejo-runner + build tools)
```

## Version Updates

All versions are centralized in `src/lib/versions.nix`. When updating:
1. Edit `src/lib/versions.nix` for language versions
2. For NixOS channel changes, also update `flake.nix` (nixpkgs.url and nixvim.url branches)

## Commit Convention

Uses Conventional Commits enforced by commitlint via lefthook pre-commit hooks. Format:
```
type(scope): description

Types: feat, fix, docs, style, refactor, perf, test, chore
```

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
- `deepwiki` - Repository documentation
- `nixos` - NixOS package/option search
- `github` - GitHub API (requires GITHUB_TOKEN)
- `gitea` - Gitea/Forgejo API (requires GITEA_TOKEN)
- `kubernetes` - Kubernetes cluster interaction

## Environment Variables

Loaded via direnv from `example.env` (defaults) and `.env` (local overrides):
- `GITHUB_TOKEN` - GitHub authentication
- `GITEA_TOKEN` - Gitea/Forgejo authentication
- `CONTAINER_REGISTRY` - Container registry (default: docker.io)
- `CONTAINER_IMAGE` - Image name (default: containercraft/konductor)
