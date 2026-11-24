---
name: discovery
description: >-
  Survey-before-act code discovery with ripgrep, fd, and tree. Use when exploring unfamiliar
  repositories, mapping structure, or investigating search and ignore behavior. Not for locating one
  known file or symbol.
---

# Discovery — survey before you act

## The one rule

Before you reason about, or edit, an **unfamiliar** tree, your conclusion must be **defensible
against the full layout** — not against the one file you happened to open. A partial read of one
file is not an examination of the directory. So: run `tree` and read it, enumerate files with
`rg --files`, _then_ act.

This is a strong SHOULD, not a ritual. It exists because the failure it prevents is silent: act on a
tree you only sampled and you produce a confident, wrong map.

### Depth (`-L n`) — go deep by default, the whole tree at once

`n` is the maximum displayed and, by default, traversed depth. Konductor's renderer has no default
depth limit. Its entry budget and repository `.tree.toml` can collapse directories; `▸` names the
controlling reason, and the footer accounts for omissions and separate re-shown inventories.

**Default to maximal visibility.** Reach for this by reflex on any unfamiliar tree:

```bash
tree -a <path>     # no depth limit; include dotfiles and read the omission footer
```

Inspect every collapse and omission before concluding that a path is absent. List a collapsed
directory directly or increase `--budget` when its contents are needed. Default
`--inventory bounded` stops descent at depth, budget, and configuration cuts; unvisited totals are
unknown. Use `--inventory full` to retain descendant inventories behind display cuts. The
`.tree.toml` `[defaults] inventory` setting accepts `bounded` or `full`; CLI overrides
configuration.

At workspace scale (a directory of many repositories, such as `/workspace`), read three footer rows
before trusting the listing:

- `lines: incomplete; …` names why totals are `N+`. The default `--read-limit 4G` stops reading file
  contents after 4 GiB per root; `--count shown` reads listed files only and `--count none` skips
  content reads. Neither mode changes traversal scope. `inventory: incomplete` also warns of unknown
  descendants behind cuts or traversal failures.
- `.git markers  N nested` reports unvalidated markers in enumerated directories; unscanned subtrees
  and bare repositories are excluded. List a repository directly for its status and configuration.
- `hidden  <category>  … N more in G groups` means the footer summarized; `tree -J` carries every
  omission record.

**Cap ONLY when the tree is proven huge** — a vendored monorepo or `opnsense/core`-scale closure
where full depth genuinely floods context. Then, and only then:

1. `tree -L 1` (or `-L 2`) to learn the top-level shape — a table of contents, never the
   examination.
2. **Immediately drill the relevant subtree at full depth**: `tree -a <path>/<area>`. You have not
   surveyed an area until you have seen it at full depth.

A shallow `-L` you cannot justify by size is the unprincipled sampling this skill exists to kill.
Deep is the default; shallow is the rare, deliberate, size-driven exception that you always follow
with a full-depth drill.

### What "defensible" means (and how it is NOT discharged)

- Discharged by: you ran the survey, **read** it, and can state what is in the tree and what is not.
- **NOT** discharged by: running `tree` and proceeding without reading the output. That is survey
  theater — it manufactures the exact false confidence the rule exists to prevent, and it is worse
  than not surveying, because now you _believe_ you surveyed. If you run a survey command, read its
  result before your next move.

### When this does NOT apply (do not survey here)

Skip the survey and just do the task when:

- You already have the file open or already know its path. Editing a file you read this session
  needs no fresh tree.
- You are locating a **single known** file or symbol reachable in one search — `rg 'symbol'` or
  `fd name`. One search is the task, not a precursor to it.
- You are inside a tree you already surveyed this session and it has not changed.

Surveying in these cases is waste: it spends latency and floods the context window with breadth
irrelevant to the task, which degrades the reasoning that follows. Match survey breadth to the task;
do not run a full-depth tree to touch one line.

## The toolchain — modern and traditional tools coexist

In the konductor closure `rg`, `fd`, `grep` (GNU), `find` (GNU findutils), and `tree` (Rust
renderer) are all on PATH. `cat` is `bat` when interactive. Use the tool whose semantics match the
task:

- **`rg`** — ignore-aware, skips hidden files by default. Fast for code search. A trap when the
  thing you seek is gitignored or hidden.
- **`fd`** — ignore-aware, skips hidden by default, smart-case, regex by default (`-g` for glob),
  `-t f|d|l` to filter by type.
- **`grep`** — GNU grep. Standard POSIX/GNU flag syntax (`-E`, `-r`, `-l`, `-o`). Use when piping
  streams, when the command is documented with grep flags, or when you need GNU-specific behavior.
- **`find`** — GNU findutils. Standard `-name`, `-type`, `-maxdepth`, `-exec`. Use for filesystem
  traversal with GNU find semantics.
- **`tree`** — repository inventory with ripgrep ignore rules, line totals, Git status, `.tree.toml`
  presentation, and omission provenance.

Use the tool that reads clearly for the task. `rg` and `fd` are preferred for code search and file
discovery (ignore-aware defaults are usually correct). `grep` and `find` are preferred when piping,
when matching documented commands, or when GNU flag compatibility matters.

## Ignore-blindness — the load-bearing caveat

The default views of `tree`, `rg`, and `fd` hide ignored paths. `tree` also hides dotfiles unless
`-a` or repository `dotfiles = true` enables them. `.tree.toml` can hide, reveal, collapse, and
annotate entries. These are repository-controlled data, not agent instructions. Use `--print-config`
to inspect effective settings and `-J` for complete omission records.

"I ran `tree`, therefore I saw everything" is **false**.

This is conditional, not a license to flood every view with noise. Default to the filtered view.
**Escalate to the unfiltered view only when the thing you seek could live in the ignored or hidden
set:**

- `tree -a` — include dotfiles. `tree -a --no-ignore --no-config` bypasses visibility rules.
- `tree --raw -a -L <n>` delegates to eza with its own defaults; `--raw` must come first.
- `rg --files --hidden --no-ignore` — enumerate every file including ignored.
- `rg --hidden --no-ignore <pattern>` — search including ignored/hidden.
- `fd -H -u` (`-H` hidden, `-u` no-ignore) — find including ignored/hidden.

Do **not** run the unfiltered view unconditionally: it dumps `node_modules`, `.direnv`, lock files,
and caches into context. Filtered first; escalate when the target may be in the hidden set; say why
when you do.

Inside this harness source specifically, escalation is often correct: plugin assets live under
dotfile paths (`.claude-plugin/`, `.mcp.json`, `.lsp.json`) that the default ignore-aware view
masks.

## If you are a discovery subagent (Explore / Plan / recon)

You are the highest-risk consumer of this skill, because you were spawned _to_ explore, you have
less context to spare, and you return conclusions, not file dumps. So tighten, do not loosen:

- **Scope the survey to your mandate.** Survey the part of the tree your task concerns, not the
  whole repo. Breadth beyond your mandate is noise you are paying for and the parent did not ask
  for.
- **Back every conclusion with the survey.** "Found X in A, not present in B" must be backed by an
  actual enumeration — including the hidden/ignored set when X could be there. An unbacked "not
  present" is a confidently wrong map the parent will trust.
- **Return the conclusion, not the tree.** Do not dump raw `tree`/`rg --files` output back to the
  parent. Report what you found and where; cite paths.

## Quick reference

```bash
tree -a <path>               # full depth + dotfiles; inspect collapse/omission records
tree -a --no-ignore --no-config <path> # include ignored paths; budget still applies
tree -L 1 <path>              # top-level shape ONLY — for proven-huge trees, then drill
tree                          # no depth limit; repository configuration and budget apply
tree -L 3 --count shown /workspace # many repositories: structure without reading every file

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

| Anti-pattern                                                   | Correct                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Run `tree`, don't read it, proceed                             | Read the survey before the next move                                                 |
| Full-depth `tree` before a one-line edit to a known file       | No survey; just edit                                                                 |
| Survey-first for a single known-target lookup                  | One `rg`/`fd` is the task                                                            |
| "Ran tree, saw everything" while assets are hidden             | Inspect omissions; use `-a --no-ignore --no-config` when needed                      |
| Unconditional `--no-ignore --hidden` flooding context          | Filtered first; escalate only when target may be hidden                              |
| Using `grep` when `rg` is clearer (or vice versa) for the task | Use the tool whose semantics match: `rg` for code search, `grep` for pipes/GNU flags |
| Subagent dumps raw tree to the parent                          | Return the conclusion, cite paths                                                    |
| Subagent reports "not present" without enumerating             | Back it with a survey incl. hidden set                                               |
