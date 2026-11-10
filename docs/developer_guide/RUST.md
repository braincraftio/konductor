# Rust development in Konductor

Konductor's Rust defaults follow [BeautifulRust](https://github.com/morganlinton/BeautifulRust),
pinned in `src/lib/versions.nix` (`beautiful-rust.rev`) and packaged by
`src/overlays/beautiful-rust.nix`.

## Toolchain

One toolchain, `languages.rustToolchain` (`src/packages/languages.nix`): rust-overlay
`rust-bin.stable.<languages.rust.version>.minimal` with `rust-src`, `rust-analyzer`, `clippy`, and
`rustfmt`. The `rust`, `full`, `konductor`, and `frontend` shells, the modules, the qcow2 image, the
OpenCode wrapper, treefmt, and the Rust checks use it. `nix build .#rust-toolchain` builds it.

Shells append `$CARGO_HOME/bin` after the Nix toolchain, so rustup proxies installed there do not
take precedence. An entry placed earlier in `PATH` by the user's own shell startup is outside
Konductor's control.

## New projects

```bash
nix flake init -t github:braincraftio/konductor#rust-library
nix flake init -t github:braincraftio/konductor#rust-application
```

Both templates use the `rust` devshell, edition 2024, and `rust-version` equal to the pinned
toolchain. `rustfmt.toml` sets the edition for per-file rustfmt (editors, treefmt, OpenCode), which
does not read `Cargo.toml`.

| Template           | `[lints]`                                                  | `clippy.toml`           |
| ------------------ | ---------------------------------------------------------- | ----------------------- |
| `rust-library`     | BeautifulRust `lints/lints.toml`, verbatim                 | BeautifulRust, verbatim |
| `rust-application` | the same table without the six keys upstream marks `[lib]` | BeautifulRust, verbatim |

Upstream states that applications can drop the `[lib]` lints. Dropping a key restores that lint's
default: `missing_docs`, `exhaustive_enums`, `print_stdout`, and `print_stderr` go quiet;
`missing_errors_doc` and `missing_panics_doc` stay enabled through `clippy::pedantic` and fire only
on `pub` items.

Existing projects keep their own `Cargo.toml` and `clippy.toml`. Konductor sets no global
`CLIPPY_CONF_DIR`. To adopt the policy in an existing crate, copy the files from
`nix build .#beautiful-rust` (`share/beautiful-rust/lints/`).

## Recommendation mapping

| BeautifulRust                                            | Konductor                                                                             | Verification                                                  |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Skills `rust-best-practices`, `rust-review`, `rust-port` | Practitioner skills in `src/harness/skill/`, from the pinned package without `evals/` | `rust-skill-delivery`; client discovery below                 |
| §1 rustfmt owns formatting                               | treefmt `*.rs` and OpenCode's formatter run the toolchain's rustfmt, edition 2024     | `treefmt` check                                               |
| §1 clippy owns idiom checks                              | Neovim and VS Code rust-analyzer `check.command = "clippy"`                           | —                                                             |
| §2 fmt, clippy `-D warnings`, test, `doc --no-deps`      | Template defaults                                                                     | `rust-template-library`, `rust-template-application`          |
| §2 lint policy in `[lints]`                              | Template `Cargo.toml` and `clippy.toml`                                               | Same checks: parsed table and byte comparison against the pin |
| Every lint in the table fires                            | Upstream `scripts/check-lints.sh` on the pinned toolchain                             | `beautiful-rust-lints`                                        |
| Every documentation example compiles                     | Upstream `scripts/check-examples.py` on the pinned toolchain                          | `beautiful-rust-examples`                                     |
| Skill and eval structure                                 | Upstream `scripts/check-skill.py`                                                     | `beautiful-rust-skill`                                        |
| §5 applications use `anyhow`                             | `rust-application` depends on `anyhow`                                                | Template check (vendored, offline)                            |
| §9 commit `Cargo.lock` for binaries                      | `rust-application/Cargo.lock`                                                         | —                                                             |
| §9 `cargo deny`, `cargo audit`                           | `cargo-deny`, `cargo-audit` in `rustPackages`                                         | Network-dependent; commands below                             |

## Google Rust Style Guide

[`rustguide.md`](https://github.com/google/styleguide/blob/72372684427af9861212ee7f1cdbb48b6f497857/rustguide.md)
at google/styleguide `72372684` (CC BY 3.0). BeautifulRust's `rust-best-practices` skill delivers a
digest of it (`references/google-rust-style-guide.md`).

Konductor adapts the skill and digest with
`src/overlays/patches/beautiful-rust-project-context.patch`. The adaptation preserves project API
contracts, framework conventions, and explicit lint policy; it distinguishes externally consumed
APIs from internal application code rather than classifying every library target as a reusable API.

The changes retain the guide's reasoning rather than importing Google build policy:

- Choose crate boundaries for responsibility, reuse, and build costs, not the presence of a
  subdirectory. Chromium's flat layout and scheduling rules are not Cargo defaults.
- Use enums where mode arguments obscure intent. The unchanged BeautifulRust Boolean lint preset is
  stricter; required signatures and clear Boolean contracts can warrant a local, explained lint
  expectation rather than an API migration.
- Choose borrowing, copying, and shared ownership by semantics, complexity, and cost. Add trait
  implementations with meaningful contracts, not merely because they derive.
- Preserve project formatting and deliberate alignment; do not use formatter suppression for
  personal style. Avoid dependencies on another crate's hidden implementation APIs.

Existing guidance already covers error contracts, simple application interfaces, iterator tradeoffs,
unsafe justification, and documentation of invariants. Those rules remain in the shared skill
instead of being duplicated in a second skill or installer. Both harness adapters consume the same
adapted package. Its `src` is also the input to the upstream skill, example, and lint checks, so
those checks target the delivered source. Each skill carries the patch and provenance identifying
its source, license, and hash.

| Guide                                                                                                                       | Konductor                                               |
| --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `max_width = 100`, `hex_literal_case = Lower`                                                                               | Template `rustfmt.toml`                                 |
| `ptr_arg`, `borrowed_box`, `should_implement_trait`, `len_without_is_empty`, `wrong_self_convention`, `new_without_default` | Default `warn` in clippy; no configuration              |
| `exhaustive_enums` for publicly exposed enums                                                                               | `rust-library` `[lints]`; omitted by `rust-application` |

## Deviations

| Recommendation                                                        | Konductor behavior | Constraint                                                                                      |
| --------------------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------- |
| §9 `cargo udeps`                                                      | Not shipped        | Requires a nightly toolchain; Konductor pins stable                                             |
| §8, §11 Miri, `cargo fuzz`                                            | Not shipped        | Require a nightly toolchain                                                                     |
| Google `imports_granularity = Module`, `format_macro_matchers = true` | Not set            | Nightly-only rustfmt options; stable rustfmt rejects them                                       |
| BeautifulRust MCP server                                              | Not integrated     | Its entrypoint is an HTTP handler, not a stdio executable; skill delivery does not depend on it |

## Verification outside `nix flake check`

These need network access, credentials, or nested Nix:

```bash
# Dependency advisories (RustSec database)
cargo audit
cargo deny check advisories

# Upstream behavioral evaluations (model runs, billed)
claude plugin eval "$(nix build --print-out-paths .#beautiful-rust)/share/beautiful-rust/evals/rust-review"

# OpenCode skill discovery: skills load after server startup; query once loaded
opencode api skill.list --param "location[directory]=$PWD"

# Claude plugin inventory, from an isolated CLAUDE_CONFIG_DIR
claude plugin marketplace add "$(nix build --print-out-paths .#claude-plugins)"
claude plugin install konductor-practitioner@konductor
claude plugin details konductor-practitioner
```
