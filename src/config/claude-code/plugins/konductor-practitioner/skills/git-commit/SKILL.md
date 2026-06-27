---
name: git-commit
description: Full commit ceremony — capacity planning, full-diff reading, verification gates. Invoke explicitly when committing into a repository with its own contributing/commit conventions that must be reconciled with the baseline. The commit convention itself is the always-loaded commits rule; this skill is the heavyweight procedure.
disable-model-invocation: true
---

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! ABSOLUTE PROHIBITION - VIOLATION MEANS IMMEDIATE TERMINATION OF CEREMONY !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

## YOU MUST NEVER TRUNCATE ANY OUTPUT

Before you execute ANY command, check if you are about to use ANY of these:

```
| head          <- FORBIDDEN - STOPS CEREMONY
| tail          <- FORBIDDEN - STOPS CEREMONY
| head -N       <- FORBIDDEN - STOPS CEREMONY (N = any number)
| tail -N       <- FORBIDDEN - STOPS CEREMONY
> file.txt      <- FORBIDDEN - STOPS CEREMONY
2>&1 | head     <- FORBIDDEN - STOPS CEREMONY
--stat (alone)  <- INSUFFICIENT - NOT A SUBSTITUTE FOR FULL DIFF
--oneline       <- FORBIDDEN - HIDES COMMIT BODIES
--shortstat     <- FORBIDDEN - STOPS CEREMONY
```

The ONLY acceptable patterns for reading diffs and logs:

```bash
git --no-pager diff --staged     # full staged diff
git --no-pager diff              # full unstaged diff
git log -N                       # N commits, FULL messages
git log -1 --format=fuller       # verify a commit
```

If you truncate, the ceremony has failed. There is no recovery.

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! END ABSOLUTE PROHIBITION                                                  !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

## Conventional Commits (v1.0.0)

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

## Critical mandates — non-negotiable

### 1. Read the full diff before every commit
Never commit a line you did not read. Before EVERY `git commit`:
1. `git --no-pager diff --staged`
2. Read the complete output, every line
3. Only then commit

### 2. Never truncate or bypass diff output
See the prohibition block above. `--stat`/`--numstat` are for measuring chunk
size, never a substitute for reading the patch.

### 3. Keep commits small enough to read
If you cannot read the full staged diff in one pass, the commit is too large:
`git reset HEAD <file>`, stage a smaller logical group, commit, repeat. Aim for
diffs under ~500 lines; generated/lock files may be larger but must still be read.

### 4. Never commit files that don't belong
Before staging, verify each file belongs in history. Never stage (unless
explicitly instructed): `.env` / `.env.*`, `*.secret`, `*credentials*`, `*.pem`
/ `*.key` / `*.p12`, `kubeconfig` / `*kubeconfig*`, `*token*`, `*password*`,
`node_modules/` / `vendor/`, `*.log` / `logs/`, `*.pyc` / `__pycache__/`,
`.DS_Store`, `*.swp` / `*~`, `dist/` / `build/` / `out/`, binaries >10MB,
`TASKS.*.md` planning artifacts. Run `git status --ignored` to see what exists
locally but is filtered. If a name looks suspicious, ask before staging.

### 5. Never change directories — always `git -C <path>`
NEVER `cd`. `cd <dir> && git …` is forbidden. Every git invocation specifies its
repository explicitly with `git -C <path> …` (or runs against the cwd when that
IS the target). `git -C` is unconditional: it mutates no shell state, never
depends on or leaves a changed cwd, and works identically from anywhere — so use
it always, not only "in a subdirectory". This applies to every command in the
ceremony: `git -C "$repo" status`, `git -C "$repo" --no-pager diff --staged`,
`git -C "$repo" commit …`, `git -C "$repo" log -1 --format=fuller`.

## Ceremony

### Step 1 — Gather state
```bash
git status
git status --ignored
git diff --numstat
git diff --staged --numstat
git log -5
```
Use `--numstat` to MEASURE; read full diffs after planning chunks. Never
`--oneline` — full messages reveal the project's commit style.

### Step 2 — Analyze
What changed, why, impact, does it belong, is it too large for one commit.

### Step 3 — Capacity plan BEFORE staging
Measure with `--numstat` (`<added>\t<deleted>\t<path>`); new files via `wc -l`
(×~1.3). Categorize: deletions/renames cheap, large additions (>200 lines) stage
1–2 files max. Plan chunks before any `git add`. If you stage then discover the
diff is too large, you failed to plan: `git reset HEAD`, re-plan.

### Step 4 — Stage logical groups
Stage related changes together; never mix unrelated changes. `git add <files>`
(never `git add .` / `-A` / `-p` / `-i`).

### Step 5 — Read the full staged diff (MANDATORY)
```bash
git --no-pager diff --staged
```
Read every line. Verify no secrets, no forbidden files. If too large to read,
stop, unstage some files, restage smaller, return here.

### Step 6 — Fix any problem you find before committing
If review reveals doc rot, stale refs, wrong values, TODO/FIXME, known bugs, or
outdated comments: fix it, re-stage, re-read, then continue. Never commit a known
problem with a "fix later" note.

### Step 7 — Type, breaking change, message
Types: `feat` (MINOR), `fix` (PATCH), `docs`, `style`, `refactor`, `perf`,
`test`, `build`, `ci`, `chore`, `revert`. Breaking: `type(scope)!: ...` or a
`BREAKING CHANGE:` footer.

Description: imperative, lowercase, no trailing period, <72 chars, WHAT not HOW.
Body (blank line after subject, wrap ~72): include when multiple changes, 3+
files, non-obvious implementation, or a breaking change needs detail. Explain
WHAT and WHY with the failure mode and the mechanism of the fix.

### Step 8 — Footers
`Fixes #123`, `Refs #456`, `BREAKING CHANGE:` (uppercase). NEVER include
`Co-authored-by:` with AI names, `Signed-off-by:` with AI identities, or any PII
beyond what git config already records.

### Step 9 — Commit
```bash
git commit -m "type(scope): description"
```
Multi-line via repeated `-m` or a quoted heredoc body.

### Step 10 — Verify
```bash
git status
git log -1 --format=fuller
```
Report: short hash, full message, files changed, remaining unstaged.

### Step 11 — Continue or complete
If unstaged changes remain, count them, ask whether to continue, and if yes
return to Step 4.

## The golden rule

READ BEFORE YOU COMMIT. `git add <files>` → `git --no-pager diff --staged`
(read every line) → `git commit`. If you cannot read the full diff, the commit
is too large — split it. Never truncate. Never skip. Never assume.

## Examples

```
fix(parser): handle multiple spaces in array literals
```

```
fix(cloudinit): create home dirs at boot, not at login

profile.d runs on interactive login, after systemd user services start via
linger. Those services need ~/.config/state to exist for ReadWritePaths
namespace setup, so first boot fails with exit 226/NAMESPACE. Move the skel copy
into cloud-init runcmd, which runs at boot after user creation and before any
service start.
```

```
chore(deps): update lockfile

- nixpkgs: 89dbf01 -> 30a3c51
- rust-overlay: 03c6e38 -> 056ce5b
```
