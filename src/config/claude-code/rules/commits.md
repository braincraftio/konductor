# Commit & PR convention

The default commit convention for every repository. A repository that defines
its own convention (CONTRIBUTING, commitlint config, or its own commit rule)
takes precedence for format and scope; the Hard rules below always apply.

Commit messages are read by humans (reviewers, maintainers, future readers) and
by machines (LLM context, changelog generation, semantic-release version bumps).
Both audiences want the same thing: precise, objective technical fact — not
narrative.

## Format — Conventional Commits v1.0.0

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

- `type`: `feat` (MINOR), `fix` (PATCH), plus `build`, `chore`, `ci`, `docs`,
  `perf`, `refactor`, `revert`, `style`, `test`.
- `scope`: optional noun for the affected section, in parentheses — `fix(parser):`.
- `description`: imperative, lowercase, no trailing period, immediately after the
  colon+space, summarizing the change. Keep the subject line concise.
- Body begins one blank line after the description; free-form, newline-separated
  paragraphs; wrap at ~72 columns.
- Footers begin one blank line after the body. Each footer is `Token: value` or
  `Token #value`; the token uses `-` for spaces (`Reviewed-by`, `Refs`). Value
  may span lines until the next footer token.

## Breaking changes

- Indicate in the prefix with `!` before the colon — `feat(api)!: …` — or as a
  footer `BREAKING CHANGE: <description>` (uppercase; `BREAKING-CHANGE` is
  synonymous). A breaking change MAY accompany any type and correlates with a
  MAJOR bump. If `!` is used, the footer MAY be omitted and the description
  describes the break.

## Revert

- Use the `revert` type with a footer referencing the reverted SHAs:
  ```
  revert: <subject of the reverted change>

  Refs: 676104e, a215868
  ```

## Body — verbose, exhaustive, diff-derived technicals only

The body is derived from the diff, nothing else, and it is thorough. Enumerate
every meaningful change at the mechanism level — do not summarize away detail.
The bar is "a reader could reconstruct what changed and why from the body alone."

- Exhaustive, not terse. Group by concern or by file/area with a labeled section
  per group; under each, bullet the specific changes (fields added, functions
  renamed, values corrected, resources created). A multi-area change gets
  multiple labeled sections.
- Objective present-tense fact. State what the change does and the mechanism by
  which it does it; for a fix, state the failure mode and the mechanism of the
  fix.
- No narrative, no storytelling — do not describe the process of arriving at the
  change, what was tried, or how the work felt.
- No past or future framing — not "I noticed…", "this used to…", "we will
  later…".
- No speculation, no intent prose — only operationalized detail extractable from
  the diff. Include concrete values: paths, ports, IPs, version bumps, exit codes.

A correct body reads like a changelog entry and the release notes, because it
becomes both.

## When to include a body

Include a body when: multiple logical changes, a non-obvious implementation, a
breaking change needing detail, or the change touches several files. A single
obvious change MAY omit the body.

## Hard rules (always apply, regardless of repo convention)

- No AI attribution. No PII. No `Co-Authored-By`, no "Generated with…", no
  session-link trailer, no `Signed-off-by` with an AI identity, no names or
  emails beyond what git config already records.
- One logical change per commit. If a change spans more than one type, split it.
- Read the full staged diff before every commit. Never truncate diff output:
  no `| head`, `| tail`, `--oneline`, `--shortstat`, `> file`. Use
  `git --no-pager diff --staged` and `git log --format=fuller`.
- If you cannot read the full diff in one pass, the commit is too large — split.
- Never stage secrets or generated credentials: `.env*`, `secrets/`, `*.pem`,
  `*.key`, `*.p12`, `*credentials*`, `*token*`, and similar.
- Never `cd`. Always `git -C <path> …` — it mutates no shell state and works
  from anywhere; `cd <dir> && git …` is forbidden.
- Commit when asked; never `push`, `reset --hard`, or force-push without explicit
  instruction.

## Examples

Trivial, single obvious change — subject only:

```
fix(parser): handle multiple spaces in array literals
```

Multi-area change — labeled sections, exhaustive enumeration:

```
feat(gateway): add WebSocket support and multi-user routing

Service:
- Set appProtocol to kubernetes.io/wss for terminal Service ports
- Create one BackendTrafficPolicy per HTTPRoute for WebSocket services
- timeout.maxStreamDuration=0s (unlimited persistent stream)
- timeout.idle=24h (prevent premature connection closure)
- timeout.request=60s (initial connection establishment)

Routes:
- Add per-user HTTPRoute creation for terminal service types
- Bidirectional route<->service validation
- Port collision validation across all service types

Policy spec:
- Add enable_websocket flag to BackendTrafficPolicySpec
- build_http_upgrade() generates the upgrade config
- Policy applies only to routes prefixed terminal-
```

Bug fix — failure mode then mechanism, with concrete values:

```
fix(cloudinit): create home dirs at boot, not at login

profile.d runs on interactive login, after systemd user services start via
linger. Those services require ~/.config/state to exist for ReadWritePaths
namespace setup, so first boot fails with exit 226/NAMESPACE.

Move the skel copy from profile.d into cloud-init runcmd, which runs at boot
after user creation and before any service start. Iterate /home/*, copy skel
files, create required directories, chown to user:users.
```

Breaking change:

```
feat(api)!: send confirmation email when a product ships

BREAKING CHANGE: order webhooks now fire on ship, not on payment.
```

Dependency update — enumerate the bumps:

```
chore(deps): update lockfile

- foo: 1.4.2 -> 1.5.0
- bar: 0.9.1 -> 0.9.3
```
