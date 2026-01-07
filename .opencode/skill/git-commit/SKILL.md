---
name: git-commit
description: Create conventional commits following conventionalcommits.org v1.0.0 specification
---

## Conventional Commits Specification (v1.0.0)

This skill implements the [Conventional Commits](https://conventionalcommits.org/en/v1.0.0/)
specification for machine-parseable, SemVer-compatible commit messages.

### Commit Message Structure

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

## Commit Ceremony

Execute these steps in order. Do NOT skip steps.

### Step 1: Gather State

Run ALL of these commands in parallel:

```bash
git status                      # Working tree state
git diff                        # Unstaged changes  
git diff --staged               # Staged changes
git log -5                      # Recent commits with full messages
```

**NEVER use `--oneline`** - always show full commit messages to understand
the project's commit style including body formatting.

### Step 2: Analyze Changes

Before staging, determine:

1. **What changed?** - List modified files and their purpose
2. **Why did it change?** - The motivation (fix bug, add feature, refactor)
3. **What is the impact?** - Does it break existing behavior?

### Step 3: Stage Logical Groups

MUST stage related changes together. MUST NOT mix unrelated changes.

| Scope | Files | Example |
|-------|-------|---------|
| `neovim` | `src/programs/neovim/*` | keymaps, plugins, options |
| `flake` | `flake.nix`, `src/devshells/*` | nix config, shells |
| `opencode` | `opencode.json`, `.opencode/*` | ai config, skills |
| `qcow2` | `src/qcow2/*` | vm image config |
| `docs` | `README.md`, `docs/*` | documentation |
| `deps` | `flake.lock` alone | dependency updates |

```bash
git add <files>
git diff --staged               # MUST review before commit
```

### Step 4: Determine Commit Type

Select ONE type based on the primary change:

| Type | SemVer | Use When |
|------|--------|----------|
| `feat` | MINOR | Adding new functionality |
| `fix` | PATCH | Correcting a bug |
| `docs` | - | Documentation only changes |
| `style` | - | Formatting, whitespace (no code change) |
| `refactor` | - | Code restructuring (no behavior change) |
| `perf` | PATCH | Performance improvement |
| `test` | - | Adding or fixing tests |
| `build` | - | Build system or dependencies |
| `ci` | - | CI/CD configuration |
| `chore` | - | Maintenance tasks |
| `revert` | varies | Reverting previous commit |

### Step 5: Check for Breaking Changes

A breaking change:
- Removes or renames public API
- Changes behavior that consumers depend on
- Requires consumers to modify their code

If breaking change exists:
- Add `!` before the colon: `feat(api)!: remove deprecated endpoint`
- OR add footer: `BREAKING CHANGE: description of what breaks`

### Step 6: Write Description

The description MUST:
- Immediately follow the colon and space
- Be lowercase (except proper nouns)
- Use imperative mood ("add" not "added" or "adds")
- Not end with a period
- Be under 72 characters
- Summarize WHAT changed, not HOW

### Step 7: Decide on Body

Include a body when ANY of these apply:

| Condition | Action |
|-----------|--------|
| Multiple logical changes in one commit | MUST include body |
| Change requires explanation of WHY | SHOULD include body |
| Commit touches 3+ files | SHOULD include body |
| Breaking change needs detail | MUST include body |
| Non-obvious implementation | SHOULD include body |
| Simple single-file change | MAY omit body |
| Description fully explains change | MAY omit body |

Body format:
- Blank line after description
- Wrap at 72 characters
- Explain WHAT and WHY, not HOW
- Use bullet points for multiple items
- Free-form paragraphs allowed

### Step 8: Add Footers (if needed)

Footer format: `Token: value` or `Token #value`

| Footer | Use When |
|--------|----------|
| `BREAKING CHANGE:` | API/behavior breaking (MUST be uppercase) |
| `Fixes #123` | Closes an issue |
| `Refs #456` | References related issue |
| `Reviewed-by:` | Code review attribution |

NEVER include:
- `Co-authored-by:` with AI names
- `Signed-off-by:` with AI identities  
- Any PII (emails, usernames) not already public in git config

### Step 9: Execute Commit

For subject-only commits:
```bash
git commit -m "type(scope): description"
```

For commits with body:
```bash
git commit -m "type(scope): description

- first change explanation
- second change explanation
- third change explanation"
```

For commits with body and footer:
```bash
git commit -m "type(scope): description

Explanation of the change and its motivation.

BREAKING CHANGE: description of what breaks"
```

### Step 10: Verify Success

MUST run after every commit:

```bash
git status                      # Confirm state
git log -1 --format=fuller      # Show FULL commit (not oneline)
```

Report to user:
- Commit hash (short)
- Full commit message (type, scope, description, body if present)
- Files changed count
- Remaining unstaged changes (if any)

### Step 11: Continue or Complete

If unstaged changes remain:
1. Count remaining files
2. Ask: "N files remain unstaged. Continue with another commit?"
3. If yes, return to Step 3

## Quality Checklist

Before executing commit, verify:

- [ ] Type matches the primary change purpose
- [ ] Scope matches the affected codebase area  
- [ ] Description is lowercase imperative under 72 chars
- [ ] Body included if multiple changes or non-obvious
- [ ] No AI attribution in footers
- [ ] No PII beyond git config
- [ ] Breaking changes marked with `!` or `BREAKING CHANGE:`

## Examples

### Feature with body (correct)

```
feat(opencode): add git-commit skill for conventional commits

- implement conventionalcommits.org v1.0.0 specification
- add decision tree for body inclusion
- add breaking change detection guidance
- include quality checklist for verification
```

### Bug fix without body (correct)

```
fix(starship): silence error on dumb terminals
```

### Breaking change with footer (correct)

```
feat(api)!: change authentication to OAuth2

Migrate from API key authentication to OAuth2 flow.
Existing API keys will stop working after v2.0.0.

BREAKING CHANGE: API key authentication removed, use OAuth2 tokens
Refs #142
```

### Dependency update (correct)

```
chore(deps): update flake inputs

- nixpkgs: 89dbf01 -> 30a3c51
- nixvim: cae79c4 -> 983751b
- rust-overlay: 03c6e38 -> 056ce5b
```

### Multiple scope refactor (correct)

```
refactor(neovim): reorganize ai keymaps and fix checkhealth

keymaps:
- change ai prefix from <leader>v to <leader>a
- flatten hierarchy for direct tool access

checkhealth:
- switch nixpkgs-fmt to nixfmt-rfc-style
- disable mercurial in diffview
- disable latex in render-markdown
```

## Anti-Patterns (NEVER do these)

```
# Using --oneline (hides commit body, prevents learning style)
git log --oneline

# Vague description
fix: stuff

# Capitalized type or scope  
Fix(Flake): update config

# Past tense
feat(api): added new endpoint

# AI attribution
feat(neovim): add keymaps

Co-authored-by: Claude <claude@anthropic.com>

# Implementation chatter
fix(starship): I noticed the prompt was showing errors so I added a check...

# Missing body when needed (multiple files, non-obvious change)
refactor(neovim): reorganize ai keymaps and fix checkhealth warnings
```

## Activation

Load this skill when user:
- Says "commit", "stage and commit", "create commit"
- Asks to "prepare for PR" or "save changes"  
- Requests conventional commit format
- After completing work and asking to persist changes
