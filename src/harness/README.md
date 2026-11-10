# Harness ownership and skill delivery

```text
src/harness/
  default.nix                  composition root
  skill/
    default.nix                catalog keyed by immediate directory names
    build.nix                  shared artifact construction
    <id>/
      default.nix              scope and source directory
      SKILL.md                 native frontmatter and instructions
      scripts/                 optional executable resources
      references/              optional reference documents
      assets/                  optional supporting files
  claude-code/                 Claude configuration, hooks, agents, plugin adapter
  opencode/                    OpenCode configuration and skill-path adapter
```

## Identity and source ownership

Each immediate directory under `skill/` defines exactly one identity. The filesystem cannot contain
two entries with the same name. Every directory must provide `default.nix`; malformed definitions
fail evaluation rather than being silently skipped. IDs use lowercase letters, digits, and single
hyphens.

Authored definitions have this shape:

```nix
_:
{
  scope = "practitioner";
  directory = ./.;
}
```

`scope` is `project` for Konductor-specific workflows or `practitioner` for general workflows. Edit
`SKILL.md` directly, including its YAML frontmatter. Its `name` matches the directory ID;
`description` defines its trigger surface and `disable-model-invocation: true` marks explicit-only
invocation. Nix neither interpolates nor serializes Markdown. The complete source directory ships,
preserving relative resources and executable permissions.

Package-owned definitions use the same `scope` and `directory` interface. The directory points to
the complete immutable upstream skill, including its `SKILL.md` and relative resources. Its
dependency pin owns the upstream content; Konductor owns the catalog identity and delivery path. Do
not copy upstream content into another definition or register the same capability under aliases.

There is no recursive skill search, concatenation of independent skill catalogs, or first/last-wins
merge. The shared builder produces one immutable directory per skill and projections of those exact
directories for each scope.

## Harness boundary

`default.nix` constructs the shared catalog once and injects it into sibling adapters. Claude
materializes the scope projections inside its two plugins because its loader restricts external
symlinks. OpenCode references the full catalog directly. Neither adapter reads another adapter's
output. Shared content uses capabilities and discovered tool names, not a particular harness's MCP
namespace or session ownership conventions.

Hooks, authentication, settings, system prompts, and native agent definitions belong to their
harness. A new harness adds an adapter here and consumes the catalog; it does not copy or
re-register skills. If a harness needs a different wire format, its adapter renders that format from
shared definitions rather than importing another harness's files.

`src/config/default.nix` preserves the existing `config.claude-code` and `config.opencode` consumer
interfaces and exposes the composition as `config.harness`.

## Build outputs

- `nix build .#harness-skills`: complete shared skill directory.
- `nix build .#claude-plugins`: complete local Claude marketplace. The source repository is not a
  marketplace; the build supplies the complete plugin layouts.

Both outputs consume the same skill sources. Installing the wrapped Claude CLI continues to load
both plugins through their immutable store paths.
