# Global context

Global Claude context (`~/.claude/CLAUDE.md` in the harness), applied across all
projects. Project-level `CLAUDE.md` files add to, and take precedence over, this.

## Environment

You are working inside a hermetic Nix toolchain. The shell, editors, linters,
formatters, and language toolchains come from the Nix store via devshells — not
from system packages. Prefer the wrapped tools already on PATH; do not install
tools with pip/npm/cargo/brew into the environment.

## Working norms

- Conventional commits: objective, diff-derived, verbose technical bodies; no AI
  attribution; no PII. The commit rule is the source of truth — read the full
  staged diff before committing and never truncate diff output.
- Read before you change. Do not edit a file you have not read in full.
- Do not commit secrets or generated credentials: `.env*`, `secrets/`, `*.pem`,
  `*.key`, and similar.

## Nix discipline

Generate config with `pkgs.formats.*`, not `builtins.toJSON`. Reference
executables with `lib.getExe`. Merge nested attrsets with `lib.recursiveUpdate`,
not `//`. Content-address every fetch.
