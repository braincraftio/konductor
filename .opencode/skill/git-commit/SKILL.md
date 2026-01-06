---
name: git-commit
description: Create conventional commits with proper ceremony for konductor
---

## Commit Ceremony

When asked to commit changes, follow this structured process.

### 1. Gather State

Run these commands in parallel to understand current state:

```bash
git status                    # Untracked and modified files
git diff                      # Unstaged changes
git diff --staged             # Already staged changes
git log --oneline -5          # Recent commit style reference
```

### 2. Stage Logical Groups

Group related changes by scope. Stage one logical unit at a time:

| Scope | Files |
|-------|-------|
| neovim | `src/programs/neovim/*` |
| flake | `flake.nix`, `flake.lock`, `src/devshells/*` |
| opencode | `opencode.json`, `src/config/opencode/*`, `.opencode/*` |
| qcow2 | `src/qcow2/*` |
| docs | `README.md`, `docs/*` |
| deps | `flake.lock` only |

Stage with:
```bash
git add <files>
git diff --staged             # Review what will be committed
```

### 3. Commit Message Format

```
type(scope): subject

body (optional, wrap at 72 chars)
```

#### Types

| Type | Use For |
|------|---------|
| `feat` | New feature or capability |
| `fix` | Bug fix or correction |
| `refactor` | Code restructuring without behavior change |
| `docs` | Documentation only |
| `chore` | Maintenance (deps, config, tooling) |
| `test` | Test additions or modifications |
| `ci` | CI/CD configuration |

#### Rules

- **Subject**: lowercase, imperative mood, no period, <72 chars
- **Scope**: lowercase, matches directory or feature area
- **No attribution**: no "Co-authored-by", no names, no AI mentions
- **No PII**: no emails, usernames in commit content
- **No chatter**: no "I did this because...", no implementation narrative
- **Technical tone**: diff-derived, objective, 3rd person neutral authoritative

#### Good Examples

```
feat(opencode): add mcp servers and fix title generation

- add small_model: opencode/gpt-5-nano for free title generation
- add nixos mcp server (github:utensils/mcp-nixos)
- add github mcp server with token from environment
- add gitea mcp server for git.braincraft.io forgejo
- add kubernetes mcp server (mcp-k8s-go)
```

```
fix(flake): restrict konductor/ci devshells and qcow2 to x86_64-linux

- konductor and ci devshells require libguestfs-appliance
- qcow2 package requires libguestfs-appliance
- oci package available on all linux systems
- cross-platform shells available everywhere
```

```
refactor(neovim): reorganize ai keymaps and fix checkhealth warnings

keymaps:
- change ai prefix from <leader>v to <leader>a
- flatten hierarchy for shallow access

checkhealth fixes:
- conform.nvim: switch nixpkgs-fmt to nixfmt-rfc-style
- diffview: disable mercurial
- render-markdown: disable latex rendering
```

```
chore(deps): update flake inputs

- nixpkgs: 89dbf01 -> 30a3c51
- nixvim: cae79c4 -> 983751b
- rust-overlay: 03c6e38 -> 056ce5b
```

#### Bad Examples

```
# Too vague
fix: stuff

# Attribution (forbidden)
feat(neovim): add keymaps

Co-authored-by: Claude <claude@anthropic.com>

# Implementation chatter (forbidden)
fix(starship): I noticed the starship prompt was showing errors...

# Capitalized (wrong)
Fix(Flake): Update dependencies
```

### 4. Execute Commit

```bash
git commit -m "type(scope): subject"
# Or with body:
git commit -m "type(scope): subject

- bullet point 1
- bullet point 2"
```

### 5. Verify and Report

```bash
git status                    # Confirm clean or remaining changes
git log --oneline -1          # Show committed
```

Report:
- What was committed (files, scope)
- Commit hash (short)
- Remaining unstaged changes if any

### 6. Continue or Complete

If unstaged changes remain, ask:
> "There are N more files with changes. Continue with another commit?"

Group remaining changes logically and repeat.

## When to Use This Skill

- User says "commit", "stage and commit", "create commits"
- User asks to "prepare changes for PR"
- After completing a task when user asks to save work
- When reviewing `git status` shows changes to commit
