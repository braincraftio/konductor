# CLAUDE.md — Konductor Claude Code harness

Guidance for working inside `src/config/claude-code/`. This is the source for the
konductor-wrapped `claude` CLI and its shipped assets. Read this before editing
anything here.

## What this directory is

A self-contained, **hermetic** Claude Code harness. One wrapped `claude` binary
delivers two channels of content, all from a single Nix flake closure:

1. **User-tier config** → a content-addressed `linkFarm` (`configDirDrv` in
   `default.nix`). The wrapper seeds a *writable* `~/.config/konductor-claude`,
   symlinks this read-only store content in, and points `CLAUDE_CONFIG_DIR` at
   the writable dir. Members: `settings.json` (built by `settings.nix` +
   `permissions.nix`), `CLAUDE.md` (the global `context.md`), `rules/`,
   `output-styles/`, the statusline.

2. **Capability assets** → two namespaced plugins loaded immutably from the store
   via `--plugin-dir`: `konductor` (`/konductor:*`, project-specific) and
   `konductor-practitioner` (`/konductor-practitioner:*`, project-agnostic).
   Plugins own their own skills, agents, hooks (`${CLAUDE_PLUGIN_ROOT}`),
   `.mcp.json`, and `.lsp.json`.

## How everything ships (read this before adding assets)

`default.nix` is the build. The two plugins are referenced as bare source paths:

```nix
konductorPlugin = ./plugins/konductor;
practitionerPlugin = ./plugins/konductor-practitioner;
```

A bare source path **coerces the entire directory tree into the store**. Every
`SKILL.md`, agent `.md`, `hooks.json`, hook `.sh`, `.mcp.json`, and `.lsp.json`
under a plugin is copied wholesale, content-addressed, and served by
`--plugin-dir <store path>`.

**Consequence — the rule that matters:** adding a skill, agent, or hook is
**drop-in, zero Nix edits**. Create `plugins/<plugin>/skills/<name>/SKILL.md` (or
`agents/<name>.md`) and it ships: the directory coercion picks it up, the content
hash changes, the new store path flows `plugin → wrappedClaude`, and the loader
serves it. This is how `nix-idioms` and `git-commit` already ship. You only touch
Nix when you change the harness *structure* (a new linkFarm member, a new
substituted placeholder, a new plugin), not when you add an asset to an existing
plugin.

The `claude` binary itself is `wrappedClaude`: `runCommand` slurps
`claude-wrapper.sh`, `substituteAll` bakes in the four store paths
(`@configDir@`, `@konductorPlugin@`, `@practitionerPlugin@`, `@claude@`), and
`shellcheck` gates the build. Upstream is pinned at `pkgs.unstable.claude-code` —
not "whatever npm resolved."

## Hermeticity is total and co-bound — do not hedge against it

The same closure that ships `claude` ships its toolchain and its assets together.
There is no version skew and no "tool might be missing" branch:

- `rg`, `fd`, `grep` (GNU), `find` (GNU findutils), and the `eza`-backed `tree`
  are all in the **same flake closure** as the wrapped `claude`. Both modern and
  traditional tools are on PATH — use whichever has the right semantics for the
  task. `cat` is `bat` when interactive.
- A plugin asset **cannot load in a session that lacks these tools**, because the
  closure that carries the asset carries the tools.

So when authoring skills/agents/docs here: state tool usage as **law**, the way
`nix-idioms` states nix idioms as law. Do **not** write "prefer rg if available"
or "fall back to grep" — that imports a portability concern this architecture
eliminated. The guaranteed tool is the only tool.

## Discovery discipline (tree-first, and the ignore-blindness caveat)

Before reasoning about or editing an unfamiliar tree, **survey the full layout
with `tree` first** — a partial read of one file is not an examination of the
directory. But know what the wrapped `tree` hides:

- The konductor `tree` defaults to `--git-ignore` **plus** `.treeignore`
  (`src/config/tree/`). That suppresses `.claude`, `sources/`, `dist/`,
  `node_modules/`, lock files, and build caches from the default view.
- "I ran `tree`, therefore I saw everything" is **false**. To survey hidden and
  ignored assets, use `tree -a` (show hidden) or `tree --raw -a -L <n>` (raw eza,
  no konductor filtering). To enumerate ignored files, `rg --files --hidden
  --no-ignore`.

This caveat is load-bearing in *this* directory specifically: the plugin assets
live under paths (`.claude-plugin/`, dotfile configs like `.mcp.json` /
`.lsp.json`) that the default ignore-aware view can mask.

## Where each thing lives

- `default.nix` — the harness build (`lib.makeExtensible`; every sub-concern and
  derived derivation exposed for downstream `.extend`).
- `claude-wrapper.sh` — the real wrapper script (`@placeholder@` substituted at
  build). Seeds the writable dir, shares auth via `~/.claude.json` symlink, loads
  plugins. shellcheck'd at build.
- `settings.nix` — `settings.json` content (model, effort, theme, attribution,
  `enabledPlugins`, statusline pointer). A plain attrset; serialized by
  `formats.json`, **never `builtins.toJSON`**.
- `permissions.nix` — the `permissions` object (the security surface; `defaultMode`,
  allow/deny). Isolated for review.
- `statusline.{nix,sh}` — Catppuccin Frappé powerline, a `writeShellApplication`
  with hermetic `runtimeInputs`.
- `context.md` — ships as the harness-global `CLAUDE.md` (distinct from this file).
- `rules/commits.md` — the default commit convention (yields to a repo's own).
- `output-styles/` — opt-in styles (e.g. `staff-engineer.md`).
- `setup-hook.sh` — `makeSetupHook` entry for devshell/CI consumers.
- `plugins/konductor/` — project assets: pulumi/talos/runme/qcow2 skills,
  k8s-debugger + pulumi-engineer agents, secret-scan + nix-fmt hooks, `.mcp.json`,
  `.lsp.json`.
- `plugins/konductor-practitioner/` — project-agnostic assets: `nix-idioms`,
  `git-commit`, and `discovery` skills, the `commit-guard` hook.

## Authoring conventions

- **Skill / agent frontmatter.** A skill's `description` is its trigger surface —
  it decides when the model (and discovery subagents) auto-select the skill.
  Write it to name concrete trigger conditions, not a vague topic. Add
  `disable-model-invocation: true` only for heavyweight explicit-invoke ceremonies
  (as `git-commit` does). Agents declare a `tools:` allowlist and `model:
  inherit`; keep diagnostic agents read-only and say so.
- **Hooks are non-blocking and namespaced.** Plugin hooks read the JSON blob on
  stdin, `exit 0` always (advisory, never abort the tool), degrade gracefully if
  `jq` is absent, and honor the `KONDUCTOR_CLAUDE_HOOKS_DISABLE=1` kill switch.
  Reference scripts via `${CLAUDE_PLUGIN_ROOT}/hooks/<x>.sh`.
- **Two plugins, two tiers.** Project-specific (Konductor platform) → `konductor`.
  Project-agnostic (any Nix/Linux repo) → `konductor-practitioner`. Pick by
  whether the asset names Konductor-specific paths/clusters/pipelines.
- **Nix idioms apply here too.** `formats.json` not `toJSON`; `lib.getExe` not a
  bare `${drv}`; `lib.recursiveUpdate` for nested merges; reference derived values
  through `final.*` so `.extend` propagates. See the `nix-idioms` skill.

## Runtime configuration and settings layering

The wrapper **does not** create `settings.local.json`. That's the user's file for
runtime mutations (`/login`, UI preference changes). Claude Code auto-merges when
both exist: `settings.json` (hermetic base) + `settings.local.json` (user
overrides), with local winning for scalar values and permission rules merging.

**For provider-specific config** (AWS Bedrock, GCP Vertex, Azure), set env vars in
the consuming flake's home-manager config, NOT in konductor's shipped defaults:

```nix
# ~/.config/home-manager/hosts/cisco.nix
home.sessionVariables = {
  CLAUDE_CODE_USE_BEDROCK = "1";
  AWS_REGION = "us-east-1";
  AWS_PROFILE = "default";
  ANTHROPIC_DEFAULT_SONNET_MODEL = "us.anthropic.claude-sonnet-4-5-20250929-v1:0[1m]";
  ANTHROPIC_DEFAULT_OPUS_MODEL = "us.anthropic.claude-opus-4-6-v1[1m]";
  ANTHROPIC_DEFAULT_HAIKU_MODEL = "us.anthropic.claude-haiku-4-5-20251001-v1:0";
};
```

Or in project `.envrc` for per-workspace overrides. The `/login` command writes to
`settings.local.json` when that path is writable; the konductor wrapper seeds a
writable `~/.config/konductor-claude/` so writes succeed.

## Verifying a change

After editing, the build is the verification:

```bash
nix build .#                  # or the harness attr; default.nix is shellcheck-gated
```

`claude-wrapper.sh` is shellcheck'd inside `wrappedClaude`; a wrapper edit that
fails shellcheck fails the build. For a settings/permissions change, the
`formats.json` derivation validates JSON shape at build time.
