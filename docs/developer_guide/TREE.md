# Repository tree

Konductor's `tree` renders a repository inventory with line totals, Git status, ignore provenance,
and explicit expansion limits.

```bash
tree
tree -L 2
tree -s src
tree -h src
tree -a --no-ignore --no-config
tree -J src
tree --init .
tree --print-config .
tree --raw --help
```

## Reading the listing

The global columns are `LINES`, `GIT`, and `PATH`. `-s` adds byte sizes; `-h` adds human-readable
sizes and takes precedence over `-s`. Directory line totals aggregate represented regular files,
including scanned ordinary descendants whose rows are collapsed. Re-shown ignored subtrees are
excluded from ancestor totals and reported separately.

| Display         | Meaning                                     |
| --------------- | ------------------------------------------- |
| `42`            | Complete text line count                    |
| `42+`           | Known lines with additional files uncounted |
| `—`             | No line count available                     |
| `bin`           | Binary file                                 |
| `[too large]`   | File exceeds the 64 MiB counting limit      |
| `[unreadable]`  | File contents could not be read             |
| `[read limit]`  | Not read: `--read-limit` total was reached  |
| `[not counted]` | `--count none` (or `shown`, if unlisted)    |

Counts include a final unterminated line, unlike `wc -l`. Binary detection checks for NUL in the
first 8,000 bytes. Sizes are apparent byte lengths, not allocated disk usage. Binary files
contribute zero text lines without making ancestor totals incomplete. The 64 MiB limit applies to
bytes actually read, so a file that grows during the run is still capped.

### Work bounds

`--inventory bounded` is the default. Depth, entry budget, and configuration collapse stop descent;
unvisited directory totals are unknown, not zero. Ancestors retain observed lower bounds.
`--inventory full` traverses ordinary descendants behind presentation cuts to retain their totals.
Set `[defaults] inventory = "full"` in `.tree.toml` for a persistent preference; either CLI mode
overrides configuration. `--print-config` reports the selected mode and its source.

Bounded traversal admits entries in deterministic byte-name depth-first order. After the entry
allowance is consumed, subsequent directories are not descended into. Already-open directories
finish enumerating their immediate entries, so the traversal allowance is a directory-granular
bound, not a hard entry or memory ceiling. The presentation budget then collapses directories to fit
output; the root always expands. Full inventory uses only the presentation budget.

Content counting is independent of traversal:

- `--count all` (default) makes every scanned, represented file eligible for counting.
  `--count shown` reads listed files only; `--count none` reads no file contents.
- `--read-limit <size>` (default `4G`; `K`/`M`/`G`/`T` are binary; `unlimited`) caps actual content
  bytes read **per listing root**. Listed files have priority, then files inside scanned collapsed
  directories, each in listing order. Finite allowances are consumed sequentially; unlimited
  counting is parallel. Binary probes and failed opens leave unused allowance available. Candidates
  larger than the remaining allowance are skipped. Depth and budget can therefore change partial
  line totals. Counting is not a filesystem snapshot.

Counting runs after depth and budget cuts and after `-P`, so files that are not represented are
never read. The footer's `lines: incomplete; …` row names every cause with its count.

Single-run measurements of the same release binary on `/workspace` at `-L 3` took 17 ms with
defaults, 12 ms with `--count none`, and 10.10 s with `--inventory full --count none`. Cache state
and host load were uncontrolled; these are observations, not latency guarantees. Full-inventory
memory grows with entries traversed, not rows displayed.

File Git columns preserve porcelain's index and worktree positions. A `+` means multiple records,
printed on the following detail line, separated by `|` with spaces shown as `␠`. JSON retains the
exact spaces. Directory `*` means changes below, not a porcelain status for that directory. Tracked
paths deleted from disk are listed in the footer. Deleted JSON records retain `path` and exact
two-column `git` status.

`▸` marks unexpanded contents. Depth cuts use only that marker; the footer states the depth once per
root. `[budget]` and `[.tree.toml]` distinguish other controlling limits. Increase `-L` or
`--budget` for those limits; edit the matching section or use `--no-config` for configuration
collapse. The root always expands, even when its immediate children exceed the budget.

Collapsed re-shown directories are not traversed by default: their inventory is unknown, not zero.
`--scan-collapsed` requests streaming file/byte counts without reading contents or constructing
descendant nodes. Set `collapse = false` to expand a whitelisted tree, or list that directory
directly. `!` controls visibility; it does not require scanning a collapsed tree.

`[hidden: N]` counts immediate omitted boundary entries. A directory containing only hidden entries
displays `—`, rather than appearing empty.

Names and notes escape backslashes, control characters, and Unicode directional controls. Names also
escape invalid UTF-8 bytes. Symlinks use reversible target escaping without recursively following
targets; JSON emits `target_bytes` for non-UTF-8 targets. Terminal and redirected listings contain
the same information; automatic color is enabled only for terminal output. `-C` and `-n` select
color explicitly.

## Visibility and provenance

Base visibility uses ripgrep's ignore machinery: `.rgignore`, `.ignore`, `.gitignore`, repository
excludes, and global Git ignores. Parent ignore files can affect the view. For example, a parent
`.rgignore` containing `*.qcow2` can hide a tracked `Dockerfile.qcow2` that Git explicitly
whitelists.

The footer groups omitted boundary paths by category, source, and pattern. A hidden directory
represents its subtree; its descendants are not individually enumerated. Counts describe omitted
boundary entries, not every descendant. A `paths relative to <root>` row states the base of every
relative path below it. The 20 largest groups get rows, printed in path order; the remaining groups
collapse into one `… N more in G groups from S sources` row per category. The `source: pattern`
column pads to at most 48 characters, so one long rule cannot widen every row. Name lists show at
most ten entries, with `tree -J` exposing all omission records. Category-specific reveal commands
appear once and run from the listing root. The `.git` metadata directory remains collapsed in
ordinary listings. Routine `.git` metadata omissions remain in JSON but do not add text footer rows.
The LINES width follows displayed values, sibling notes align, and notes follow hidden-entry
annotations. Omission rows precede configuration details and the conditional marker legend. The text
footer is capped at 8192 UTF-8 bytes per root, including newline/color overhead, with individual
rows capped at 512 bytes. Diagnostics and accounting take priority over samples. JSON retains all
recorded details; it does not invent records for unvisited subtrees.

The walker determines visibility; the explanation layer identifies the controlling rule, reading
ignore files exactly as ripgrep's `create_gitignore` does (`crates/ignore/src/dir.rs`): a read or
parse failure is partial and non-fatal. An ignore-file name that is a directory, or a file with an
invalid line, contributes the rules that could be read, and the failure is listed once under
`errors:`. Omissions with no matching rule have category `disagreement`, an error, and no entry in
`hidden.ignore_rules`. Global Git ignore rules require a Git or Jujutsu repository marker and use
the process working directory for anchored matching, as upstream does.

Omission accounting enumerates immediate entries in each visited directory after the walker. The
public ignore walker rejects ignored entries before invoking its entry callback, so this second
enumeration supplies the omitted boundary names without making the explanation layer responsible for
visibility. Collapsed re-shown directories bypass both enumerations of descendants; explicit
metadata scans use one streaming traversal.

Git status and `.tree.toml` apply to the listing root's repository only. Directories below the root
that hold their own `.git` are listed as `.git markers  N nested` in the footer and as
`nested_git_markers` path objects in JSON. These markers are unvalidated; reporting excludes
unscanned/ignored subtrees and bare repositories. List one directly to apply its status and
configuration. Git status itself remains a separate repository operation.

`-I` excludes matching names; `-P` selects matching regular files. Unsupported options fail rather
than being silently ignored. `--` ends option parsing. `--raw` passes following arguments to
`eza --tree`. `--raw` must be the first argument.

## Repository configuration

The nearest `.tree.toml` is discovered from the listed root upward, stopping at the Git root.
Outside Git, only the listed directory is searched. Files are not merged. CLI options override
configuration; configuration overrides built-in defaults.

```toml
gitignore = true
dotfiles = false
ignore = ["!/target/"]

[defaults]
level = 0
budget = 12000
inventory = "bounded" # bounded | full
count = "all"       # all | shown | none
read_limit = "4G"   # or "unlimited"
sizes = false
git = true

["/target/"]
collapse = true
note = "Cargo build output"
```

`ignore` uses gitignore syntax, including `!` to reveal paths. Leading `/` anchors a pattern to the
configuration directory. Sections control presentation; later matching sections override attributes
they specify. Unknown fields and invalid types fail. Unused patterns appear in the footer.
Visibility rules retain their zero-based array index, so duplicate patterns and presentation
sections have independent usage records. `[defaults] sizes = true` selects human-readable sizes;
`-s` overrides it with bytes.

Configuration and notes are repository-controlled data, not instructions to an agent. Notes may
contain arbitrary prose, and visibility rules may hide repository paths. Use `--no-config` to bypass
both; inspect omission records when auditing visibility.

## Compatibility

This renderer supports the options listed by `tree --help`, not the full GNU tree interface. `-F`,
`-r`, `-t`, `--prune`, `-o`, and `--charset` are unsupported and produce errors. `-P` is supported
as a regular-file name filter. Redirect stdout to save a listing. `--raw` (alias `--no-filter`)
delegates subsequent arguments directly to `eza --tree`; those arguments follow eza's interface and
defaults.

Metadata-first is the only text layout; `--metafirst` explicitly selects that layout. `-D` appends
UTC modification times after names. JSON is a Konductor schema with one report following each root,
not GNU tree JSON.

`--init` creates a starter from top-level directories and their ignore provenance. It does not
recursively scan ignored trees or invent notes. Creation is exclusive: an existing file, including a
symlink, is never overwritten. `--print-config` emits JSON containing effective values, their
sources, CLI patterns, and ordered parsed visibility/presentation rules. Invalid UTF-8 directory
names are skipped with escaped comments by `--init`. Both operations accept one directory.

## Structured output and verification

`-J` emits an array with each root followed by its own report object. `--noreport` omits reports in
text and JSON modes. File `line_state`, directory `lines_complete`, `files_uncounted`, exact `git`
records, collapse reasons, notes, and report `omissions` preserve the corresponding text
information. `path_bytes` is emitted only for invalid UTF-8 paths. Directory aggregate Git codes use
`changes_below_codes`; file records use `git`. `represented` contains ordinary subtree totals;
`listed` counts rendered directory/file rows. `reshown` contains path/inventory pairs with `state`
equal to `not_scanned`, `incomplete`, or `complete`. Scanned inventories include `totals`;
incomplete totals describe only observed entries. The scan hint appears once in the reveal block.
Directory `inventory_complete` is false and numeric inventory fields are null when no complete
inventory is available; incomplete directories expose known lower bounds in `observed`. Report
totals are observed lower bounds when report `inventory_complete` is false. `inventory` echoes the
traversal mode. `content_bytes_read` records actual content reads and `read_limit_scope` is
`per_root`. `errors` lists every error and warning once. `lines_uncounted` breaks uncounted files
down by cause (`not_shown`, `read_limit`, `too_large`, `unreadable`); `count` and `read_limit` echo
the effective settings, `root_path` is the absolute base of relative paths, and `nested_git_markers`
lists unvalidated markers with byte-preserving paths. File `line_state` is one of `text`, `binary`,
`too_large`, `unreadable`, `not_counted`, `not_shown`, or `read_limit`. Git status failures and
malformed global ignore rules are reported explicitly. The `.git` placeholder is unmeasured: its
numeric inventory fields are null and its size column is `—`. Omission records retain `path_bytes`
for non-UTF-8 names, including their original parent bytes; `hidden` categories are derived from
these records.

```bash
PATH="$(nix build .#rust-toolchain --no-link --print-out-paths)/bin:$PATH"
cargo build -p konductor-tree --release
bash src/config/tree/tests/spec.sh "$PWD/target/release/tree"
bash src/config/tree/tests/consumers.sh "$PWD/target/release/tree"
nix build .#checks.x86_64-linux.tree .#checks.x86_64-linux.tree-lint
```

Use `nix develop .#tree-development` for an independent compiler, test tools, and Linux profilers,
or obtain the toolchain from `.#rust-toolchain`. The development shell does not depend on building
the renderer. The production Nix package runs unit tests and both shell specifications. Consumer
checks cover parent ignore provenance, terminal/pipe parity, deterministic output, incomplete
counts, exact Git records, configuration creation, and filter precedence inside collapsed
directories.
