---
name: runme
description: Konductor runme task pipeline workflows. Use when working with runme markdown task runners, docs/ci/ pipeline files, runme.yaml, or executing/editing tagged code blocks in the Konductor NixOS QCOW2 build pipeline.
---

# Konductor runme

Konductor's CI/build pipeline is driven by [runme](https://runme.dev): executable
markdown where tagged code blocks are tasks. The pipeline lives in `docs/ci/`.

## Layout facts

- `docs/ci/` holds the pipeline (multiple `.md` files, dozens of tagged tasks).
  Older monolithic docs under `docs/developer_guide/qcow2/` are deleted.
- Frontmatter per file is YAML: `cwd`, `shell`, `skipPrompts`, `tag`,
  `runme.version`.
- `cwd` for `docs/ci/` files is `../..` (two levels up → repo root). `verify.md`
  uses `cwd: /opt/konductor` because it runs inside the VM.
- Cross-file task calls:
  `runme run --direnv=true --load-env=false --filename <file> <task>`.

## Shell gotcha (load-bearing)

Set `shell: bash`, NOT `shell: /run/current-system/sw/bin/bash`. The NixOS
absolute path does not exist on Pop!_OS / non-NixOS hosts; runme then falls back
to a shell that strips HOME from PATH, corrupting PATH for child tasks (rm and
other coreutils become unfindable). This bit the pipeline before — keep it
`shell: bash`.

## Workflow

1. Read the file's frontmatter (`cwd`, `shell`, `tag`) before running a task —
   the working directory is almost never the file's own directory.
2. List tasks: `runme list --filename <file>`.
3. Run a single task: `runme run --filename <file> <task>`. Run a tag group:
   `runme run --all --tag <tag>`.
4. When editing a task, preserve the tag and the frontmatter contract; other
   tasks invoke it by name via `--filename`.

## Conventions

- One concern per task, noun-verb task names.
- No debug `echo` lines left in committed tasks (they leak into pipeline output).
- Tasks that operate on the workspace use the shared WORKSPACE preamble; don't
  hardcode paths.
