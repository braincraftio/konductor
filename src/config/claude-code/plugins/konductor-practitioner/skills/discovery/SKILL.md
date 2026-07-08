---
name: discovery
description: Survey-before-act discipline for code discovery and the ripgrep/fd/tree toolchain. Use when exploring an unfamiliar repository or subtree, mapping a codebase, or about to edit or reason about structure you have not yet surveyed. Also use when searching with rg/fd/tree or when grep/find behavior surprises you. NOT for locating a single known file or symbol you can reach in one search.
---

# Discovery — survey before you act

## The one rule

Before you reason about, or edit, an **unfamiliar** tree, your conclusion must be
**defensible against the full layout** — not against the one file you happened to
open. A partial read of one file is not an examination of the directory. So: run
`tree` and read it, enumerate files with `rg --files`, *then* act.

This is a strong SHOULD, not a ritual. It exists because the failure it prevents
is silent: act on a tree you only sampled and you produce a confident, wrong map.

### Depth (`-L n`) — go deep by default, the whole tree at once

`n` is the max depth `tree` descends. **The wrapper caps at 6 when `-L` is
omitted** — so bare `tree` is NOT the full tree; it silently stops at depth 6
and hands you survey theater. Seeing everything requires an explicit, large `-L`.

**Default to maximal visibility.** Reach for this by reflex on any unfamiliar
tree:

```bash
tree -a -L 200 <path>     # everything: full depth + hidden, in one shot
```

That is the aggressive default — total visibility, nothing truncated, nothing
hidden. Do not dither over picking `n`; pick a number large enough that depth is
never the limiting factor (200 is effectively unbounded for source trees).

**Cap ONLY when the tree is proven huge** — a vendored monorepo or
`opnsense/core`-scale closure where full depth genuinely floods context. Then,
and only then:

1. `tree -L 1` (or `-L 2`) to learn the top-level shape — a table of contents,
   never the examination.
2. **Immediately drill the relevant subtree at full depth**:
   `tree -a -L 200 <path>/<area>`. You have not surveyed an area until you have
   seen it at full depth.

A shallow `-L` you cannot justify by size is the unprincipled sampling this skill
exists to kill. Deep is the default; shallow is the rare, deliberate, size-driven
exception that you always follow with a full-depth drill.

### What "defensible" means (and how it is NOT discharged)

- Discharged by: you ran the survey, **read** it, and can state what is in the
  tree and what is not.
- **NOT** discharged by: running `tree` and proceeding without reading the output.
  That is survey theater — it manufactures the exact false confidence the rule
  exists to prevent, and it is worse than not surveying, because now you *believe*
  you surveyed. If you run a survey command, read its result before your next move.

### When this does NOT apply (do not survey here)

Skip the survey and just do the task when:

- You already have the file open or already know its path. Editing a file you read
  this session needs no fresh tree.
- You are locating a **single known** file or symbol reachable in one search —
  `rg 'symbol'` or `fd name`. One search is the task, not a precursor to it.
- You are inside a tree you already surveyed this session and it has not changed.

Surveying in these cases is waste: it spends latency and floods the context window
with breadth irrelevant to the task, which degrades the reasoning that follows.
Match survey breadth to the task; do not run a full-depth tree to touch one line.

## The toolchain — modern and traditional tools coexist

In the konductor closure `rg`, `fd`, `grep` (GNU), `find` (GNU findutils), and
`tree` (eza-backed) are all on PATH. `cat` is `bat` when interactive. Use the
tool whose semantics match the task:

- **`rg`** — ignore-aware, skips hidden files by default. Fast for code search.
  A trap when the thing you seek is gitignored or hidden.
- **`fd`** — ignore-aware, skips hidden by default, smart-case, regex by default
  (`-g` for glob), `-t f|d|l` to filter by type.
- **`grep`** — GNU grep. Standard POSIX/GNU flag syntax (`-E`, `-r`, `-l`, `-o`).
  Use when piping streams, when the command is documented with grep flags, or
  when you need GNU-specific behavior.
- **`find`** — GNU findutils. Standard `-name`, `-type`, `-maxdepth`, `-exec`.
  Use for filesystem traversal with GNU find semantics.
- **`tree`** — `eza --tree` with `--git-ignore` + `.treeignore`, depth 6.

Use the tool that reads clearly for the task. `rg` and `fd` are preferred for
code search and file discovery (ignore-aware defaults are usually correct).
`grep` and `find` are preferred when piping, when matching documented commands,
or when GNU flag compatibility matters.

## Ignore-blindness — the load-bearing caveat

The default views of `tree`, `rg`, and `fd` all **hide** ignored and hidden
paths. Concretely, the konductor `tree` suppresses `.claude`, `sources/`, `dist/`,
`node_modules/`, `.direnv`, lock files, and build caches (see
`src/config/tree/.treeignore`); `rg`/`fd` skip dotfiles and `.gitignore` entries.

"I ran `tree`, therefore I saw everything" is **false**.

This is conditional, not a license to flood every view with noise. Default to the
filtered view. **Escalate to the unfiltered view only when the thing you seek
could live in the ignored or hidden set:**

- `tree -a` — include hidden. `tree --raw -a -L <n>` — raw eza, no konductor
  filtering at all.
- `rg --files --hidden --no-ignore` — enumerate every file including ignored.
- `rg --hidden --no-ignore <pattern>` — search including ignored/hidden.
- `fd -H -u` (`-H` hidden, `-u` no-ignore) — find including ignored/hidden.

Do **not** run the unfiltered view unconditionally: it dumps `node_modules`,
`.direnv`, lock files, and caches into context — the exact noise `.treeignore`
exists to suppress. Filtered first; escalate when the target may be in the hidden
set; say why when you do.

Inside this harness source specifically, escalation is often correct: plugin
assets live under dotfile paths (`.claude-plugin/`, `.mcp.json`, `.lsp.json`) that
the default ignore-aware view masks.

## If you are a discovery subagent (Explore / Plan / recon)

You are the highest-risk consumer of this skill, because you were spawned *to*
explore, you have less context to spare, and you return conclusions, not file
dumps. So tighten, do not loosen:

- **Scope the survey to your mandate.** Survey the part of the tree your task
  concerns, not the whole repo. Breadth beyond your mandate is noise you are
  paying for and the parent did not ask for.
- **Back every conclusion with the survey.** "Found X in A, not present in B"
  must be backed by an actual enumeration — including the hidden/ignored set when
  X could be there. An unbacked "not present" is a confidently wrong map the
  parent will trust.
- **Return the conclusion, not the tree.** Do not dump raw `tree`/`rg --files`
  output back to the parent. Report what you found and where; cite paths.

## Quick reference

```bash
tree -a -L 200 <path>         # DEFAULT: full depth + hidden, whole tree in one shot
tree -a -L 200 --raw <path>   # same, no konductor filtering (ignored/build dirs too)
tree -L 1 <path>              # top-level shape ONLY — for proven-huge trees, then drill
tree                          # bare tree caps at depth 6 — NOT the full tree

rg --files                    # enumerate searchable files (filtered)
rg --files --hidden --no-ignore   # enumerate EVERYTHING
rg -n 'pattern' path/         # search with line numbers
rg --hidden --no-ignore 'pat' # search including ignored/hidden

fd name                       # find by name (regex, smart-case, filtered)
fd -g '*.nix'                 # glob mode
fd -t f -e nix                # files only, .nix extension
fd -H -u name                 # include hidden + ignored
```

## Anti-patterns

| Anti-pattern | Correct |
|---|---|
| Run `tree`, don't read it, proceed | Read the survey before the next move |
| Full-depth `tree` before a one-line edit to a known file | No survey; just edit |
| Survey-first for a single known-target lookup | One `rg`/`fd` is the task |
| "Ran tree, saw everything" while assets are hidden | `tree -a` / `--raw` when target may be ignored |
| Unconditional `--no-ignore --hidden` flooding context | Filtered first; escalate only when target may be hidden |
| Using `grep` when `rg` is clearer (or vice versa) for the task | Use the tool whose semantics match: `rg` for code search, `grep` for pipes/GNU flags |
| Subagent dumps raw tree to the parent | Return the conclusion, cite paths |
| Subagent reports "not present" without enumerating | Back it with a survey incl. hidden set |
