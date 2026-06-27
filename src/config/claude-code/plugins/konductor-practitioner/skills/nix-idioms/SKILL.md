---
name: nix-idioms
description: Implementor-level Nix patterns — config generation, executables, directory trees, wrapping, module system, overridability, devshells, lib utilities. Use when writing or reviewing derivations, flake modules, or config generation.
---

# Nix Idioms — Implementor Reference

## Mental models

| Model | One-liner |
|---|---|
| Config-as-derivation | Every config file is a nix store path; no mutable state at eval time. |
| Module system as type system | `freeformType` + `mkOption` give merging, validation, priority. |
| Env-var redirect | Point `TOOL_CONFIG_DIR` at a store path instead of writing `~/.config`. |
| Overlay composition | `lib.makeExtensible` for downstream customization without forking. |
| Setup hook for devshell | `makeSetupHook` sets env via `nativeBuildInputs` propagation. |
| Wrapper owns the redirect | A `writeShellApplication` wrapper that `exec`s the binary holds runtime logic `wrapProgram` can't express. |
| passthru is the public API | Expose downstream-needed components via `passthru`; it doesn't trigger rebuilds. |

## 1. Config generation

**ALWAYS `pkgs.formats.<fmt> {}`** for config files — real derivation, pretty-printed, cacheable, `.type` for options. Formats: `json`, `toml`, `yaml`, `ini`, `keyValue`, `hocon`, …

```nix
let jsonFmt = pkgs.formats.json { };
in jsonFmt.generate "settings.json" (settings // {
  "$schema" = "https://json.schemastore.org/package.json";
})
```

**NEVER `builtins.toJSON`** for a config file (inline string, no derivation, no validation). It's only for passing JSON to a command inside a derivation.

**Typed sub-options + free-form passthrough** — `freeformType` inside a `submodule`:

```nix
settings = lib.mkOption {
  type = lib.types.submodule {
    freeformType = (pkgs.formats.json {}).type;
    options.model = lib.mkOption { type = lib.types.str; default = "claude-sonnet-4-6"; };
  };
  default = {};
};
```

Bare `formats.json.type` at top level loses the typed sub-options.

## 2. Executables

Builder decision: `writeText` (no exec) → `writeShellScript` (shebang + dry-run check) → `writeShellScriptBin` (sets `meta.mainProgram`) → **`writeShellApplication`** (deps + shellcheck + errexit/nounset/pipefail — prefer for anything non-trivial; sets `meta.mainProgram = name`).

**ALWAYS `lib.getExe`** for a command path; `lib.getExe' drv "bin"` when binary ≠ mainProgram. A bare `${drv}` is the store *directory*, not the binary.

```nix
command = lib.getExe pkgs.ripgrep;              # /nix/store/.../bin/rg
command = lib.getExe' pkgs.imagemagick "convert";
```

Hook/statusline commands → `lib.getExe scriptDrv`, never `~/.claude/hooks/x.sh` (breaks when the config dir is a store path).

## 3. Directory trees

| | `linkFarm` | `symlinkJoin` |
|---|---|---|
| Structure | Named symlinks at exact paths | Merges `bin/`/`share/` via `lndir` |
| Use for | Config dir from named sources | Combine packages into one PATH entry |
| Nested paths | Yes (`"hooks/x.sh" = drv`) | No |

```nix
configDir = pkgs.linkFarm "claude-config" {
  "settings.json"        = jsonFmt.generate "settings.json" settings;
  "rules"                = ./rules;                  # source path → store copy
  "hooks/secret-scan.sh" = lib.getExe secretScanDrv;
};
```

## 4. Wrapping binaries

`wrapProgram` flags: `--set` forces (user can't override); **`--set-default`** sets only if unset (user-overridable); `--run 'export VAR="${XDG_CONFIG_HOME:-$HOME/.config}/x"'` for runtime expansion (`--set-default` single-quotes at build time, so `$HOME`/XDG must use `--run`); `--prefix PATH : ${lib.makeBinPath [...]}`; `--add-flags`.

**When `writeShellApplication` beats `wrapProgram`:** runtime `mkdir`, conditional symlinks, multi-step seeding — logic flags can't express. Replace an existing dir before linking; never `ln -sfn` into a possibly-existing real dir (it nests the link inside):

```nix
wrapped = pkgs.writeShellApplication {
  name = "tool";
  runtimeInputs = [ pkgs.tool pkgs.coreutils ];
  text = ''
    : "''${HOME:?HOME must be set}"
    [ -n "''${TOOL_CONFIG_DIR:-}" ] && exec tool "$@"   # --set-default semantics
    CFG="''${XDG_CONFIG_HOME:-$HOME/.config}/myorg-tool"
    mkdir -p "$CFG"
    for item in settings.json config rules; do
      rm -rf "$CFG/$item"; ln -s "${configDir}/$item" "$CFG/$item"   # rm before ln, not ln -sfn
    done
    export TOOL_CONFIG_DIR="$CFG"
    exec tool "$@"
  '';
  passthru = pkgs.tool.passthru // { unwrapped = pkgs.tool; };
  meta = pkgs.tool.meta // { mainProgram = "tool"; };
};
```

**ALWAYS on wrapped packages:** `passthru = upstream.passthru // { unwrapped = upstream; … }` and `meta = upstream.meta // { mainProgram = "x"; }`. Add `priority = (upstream.meta.priority or lib.meta.defaultPriority) - 1` when the wrapper must win in `buildEnv`.

## 5. Module system

```nix
enable  = lib.mkEnableOption "harness";                 # default false
enable  = lib.mkEnableOption "hooks" // { default = true; };  # opt-out
package = lib.mkPackageOption pkgs "claude-code" { };
```

Priority ladder (lower = higher priority): `mkOptionDefault` 1500 → `mkDefault` 1000 (use for module config defaults) → regular 100 → `mkForce` 50 (sparingly). In a module's config, wrap overridable values in `mkDefault`; leave required invariants unwrapped. Combine conditional blocks with `lib.mkMerge [ (lib.mkIf …) … ]`.

## 6. Overridability

**`lib.makeExtensible (final: …)`** for a customizable value set. Derived values MUST reference `final.X` (not local `let` bindings) so `.extend` propagates:

```nix
config = lib.makeExtensible (final: let
  settingsDrv  = jsonFmt.generate "settings.json" final.settings;
  configDirDrv = pkgs.linkFarm "claude-config" { "settings.json" = final.settingsDrv; };
in { settings = import ./settings.nix { inherit lib; }; inherit settingsDrv configDirDrv; });

config.extend (final: prev: { settings = prev.settings // { model = "claude-opus-4-6"; }; })
```

`overrideAttrs (finalAttrs: prev: …)` for derivation-level overrides (two-arg form for self-reference via `finalAttrs.finalPackage`).

## 7. Merging

Flat attrsets → `//`. **Nested → `lib.recursiveUpdate lhs rhs`** (`//` is shallow, clobbers nested). In the module system → `lib.mkMerge` with priorities.

## 8. Devshell hooks

```nix
hook = pkgs.makeSetupHook {
  name = "claude-hook";
  substitutions.claudeConfigDir = configDirDrv;   # @claudeConfigDir@ in the .sh
} ./setup-hook.sh;                                 # separate file, not inline writeScript

devShells.default = pkgs.mkShell { nativeBuildInputs = [ hook ]; };
```

`mkShell`: `packages` → PATH; `inputsFrom = [ drv ]` inherits build inputs; `shellHook` strings concatenate across `inputsFrom`.

## 9. Essential lib

`lib.optionals` / `lib.optionalAttrs` / `lib.optionalString` cond x · `lib.mkIf` · `lib.makeBinPath` · `lib.escapeShellArg(s)` · `lib.concatStringsSep` / `lib.concatMapStringsSep` · `lib.recursiveUpdate` · `lib.filterAttrs` / `lib.mapAttrs` / `lib.nameValuePair` · `lib.pipe value [f g h]` · `lib.importJSON` / `lib.importTOML`.

## 10. Fetching

Content-address everything: `fetchurl`/`fetchFromGitHub` with exact url/rev + `hash`. Never unpinned. PyPI wheels: exact `files.pythonhosted.org` URL + sha256, not `fetchPypi format="wheel"`.

## Anti-patterns

| Anti-pattern | Correct |
|---|---|
| `builtins.toJSON` for config file | `(pkgs.formats.json {}).generate` |
| `${drv}` where script path needed | `lib.getExe drv` / `lib.getExe' drv "bin"` |
| `//` merging nested settings | `lib.recursiveUpdate` |
| `command = "~/.claude/hooks/x.sh"` | `lib.getExe scriptDrv` |
| Local let-binding consumed by derived `final.*` | reference through `final.X` |
| `wrapProgram --set` for user-overridable var | `--set-default` |
| `--set-default VAR "${XDG_CONFIG_HOME:-…}"` | `--run 'export VAR="${XDG_CONFIG_HOME:-…}"'` |
| `ln -sfn` into a possibly-existing dir | `rm -rf "$d" && ln -s …` |
| No `passthru.unwrapped` on a wrapper | `passthru.unwrapped = upstream` |
| `symlinkJoin` for named config layout | `linkFarm { "p/f" = drv; }` |
| `linkFarm` to combine packages on PATH | `symlinkJoin { paths = [...]; }` |
| `freeformType` at top level | `submodule { freeformType=…; options.x=…; }` |
| Unpinned fetch | always include `hash =` |
