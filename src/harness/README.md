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

## OpenCode V2 configuration

`nix build .#opencode` produces the configured CLI wrapper. Its runtime PATH is the full Konductor
package composition, excluding the wrapper itself to avoid a dependency cycle. Shells, modules, and
the installable environment use this same package. The wrapper exports its built configuration even
when launched outside a developer shell.

`opencode/config.nix` owns native server settings. `opencode/tui.nix` owns native V2 `cli.json`
settings, delivered through `OPENCODE_CLI_CONFIG_CONTENT`. The `tui` Nix attribute remains the
adapter interface; no V1 `tui.json` or migration environment variables are emitted.
`.#opencode.configDrv` and `.#opencode.tuiDrv` expose both documents.

Formatters use the same wrapped packages as developer shells, with disjoint extension assignments.
Unconfigured upstream formatter discovery is disabled. The Nix language server is explicitly named
`nil` and points to its immutable executable.

Compaction keeps 15,000 tokens with an explicit 15% buffer. The percentage deliberately does not
reproduce upstream's implicit 16,000-token minimum reserve for smaller windows. Tool output retains
up to 4,000 lines / 100 KiB. High transcript verbosity, ungrouped tools, and Mini shell output
improve visibility within upstream's supported controls; individual TUI tool renderers still
determine their own previews.

Home Manager, NixOS, and nix-darwin expose these recursive overrides:

```nix
konductor.opencode = {
  settings.compaction.keep.tokens = 20000;
  cli.attention.sound = true;
  environment.OPENCODE_DISABLE_MODELS_FETCH = "1";
};
```

Attrsets merge per leaf; arrays replace whole. Environment values and settings enter the Nix store:
credentials use runtime environment/file references. Adapter consumers can use `.extend` to override
`config`, `tui`, or `env` directly. Derived documents and the wrapper read the extended values.

OpenCode still applies its native project/global/managed configuration precedence. The shared server
retains its launch environment: an existing client can win a restart race with another build. Verify
the running server's configuration and executable paths after a deployment. Desktop presentation
preferences belong to the consuming Home Manager configuration; they are separate from server and
terminal settings.
