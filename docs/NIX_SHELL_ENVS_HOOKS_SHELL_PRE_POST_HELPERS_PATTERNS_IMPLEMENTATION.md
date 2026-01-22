# Nix Shell Environment Variables, Hooks, and Implementation Patterns

## Document Purpose

This document captures comprehensive research on Nix `mkShell` environment variable management, hooks, string escaping, and best practices. Created to preserve institutional knowledge for the Konductor devshell implementation.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [How mkShell Works](#how-mkshell-works)
3. [env Attribute vs shellHook](#env-attribute-vs-shellhook)
4. [String Escaping: Nix vs Shell](#string-escaping-nix-vs-shell)
5. [Variable Precedence](#variable-precedence)
6. [Setup Hooks](#setup-hooks)
7. [Available Hook Points](#available-hook-points)
8. [Path Construction Helpers](#path-construction-helpers)
9. [mkShell Variants](#mkshell-variants)
10. [Wrapper Patterns](#wrapper-patterns)
11. [Best Practices](#best-practices)
12. [Implementation Patterns](#implementation-patterns)
13. [The Konductor Fix](#the-konductor-fix)

---

## Problem Statement

### Observed Behavior

When running `env | grep export` in our devshell, we saw:

```
shellHook=export KONDUCTOR_SHELL="default"
export UV_SYSTEM_PYTHON="1"
export GOPATH="${GOPATH:-$HOME/go}"
...
```

### Issues Identified

1. **shellHook content visible in env output** - The entire shellHook string is stored as an environment variable
2. **Duplicate variables** - `UV_SYSTEM_PYTHON` appeared twice: once as a real env var (from `env` attribute), once as text inside shellHook
3. **Malformed env entries** - Lines with `export ` prefix appearing in env output confused tools parsing the environment

### Root Cause

We were setting the same variables in BOTH the `env` attribute AND in `shellHook` with `export` statements, causing duplication and pollution.

---

## How mkShell Works

### Architecture

```
mkShell (pkgs/build-support/mkshell/default.nix)
    │
    └── stdenv.mkDerivation (specialized wrapper)
            │
            ├── env attribute → exported before shellHook
            ├── shellHook → executed after env is set
            ├── packages → added to nativeBuildInputs → PATH
            └── inputsFrom → inherits from other derivations
```

### Key Facts

- `mkShell` is a specialized `stdenv.mkDerivation` for development shells
- The `shellHook` variable is stored as an environment variable - this is **expected and fundamental** to how nix-shell/nix develop works
- Variables from `env` attribute are exported by Nix BEFORE shellHook executes
- shellHook commands run AFTER env is set up

---

## env Attribute vs shellHook

### env Attribute

**Purpose**: Set static environment variables that don't need shell expansion

**Behavior**:
- Values are set as literal strings
- Nix expressions ARE evaluated (e.g., `${pkgs.hello}/bin` becomes `/nix/store/...`)
- Shell variables are NOT expanded (e.g., `$HOME` stays literal `$HOME`)
- Variables are exported automatically

**Use for**:
- Static values: `UV_SYSTEM_PYTHON = "1";`
- Nix store paths: `MY_TOOL = "${pkgs.sometool}/bin/tool";`
- Configuration flags: `NODE_ENV = "development";`

**Example**:
```nix
env = {
  UV_SYSTEM_PYTHON = "1";
  PYTHONDONTWRITEBYTECODE = "1";
  MY_PATH = "${pkgs.hello}/bin";  # Nix interpolation works
  # WRONG: HOME_DIR = "$HOME";    # Would be literal "$HOME"
};
```

### shellHook

**Purpose**: Execute shell commands that need runtime evaluation

**Behavior**:
- Commands executed when shell starts
- Shell variable expansion works
- Conditional logic works
- The shellHook STRING is stored as an env var (visible in `env` output)

**Use for**:
- Dynamic values needing `$HOME`: `export GOPATH="''${GOPATH:-$HOME/go}"`
- Conditional setup: `if [ -d .venv ]; then source .venv/bin/activate; fi`
- PATH manipulation depending on other vars: `export PATH="$GOBIN:$PATH"`
- Sourcing scripts: `source some-script.sh`

**Example**:
```nix
shellHook = ''
  # Dynamic with shell expansion
  export GOPATH="''${GOPATH:-$HOME/go}"
  export GOBIN="$GOPATH/bin"
  export PATH="$GOBIN:$PATH"

  # Conditional logic
  if [ -d .venv ]; then
    source .venv/bin/activate 2>/dev/null || true
  fi
'';
```

---

## String Escaping: Nix vs Shell

### Critical Distinction

| Syntax | Interpretation | When Evaluated | Example Result |
|--------|---------------|----------------|----------------|
| `${var}` | Nix interpolation | Nix eval time | Nix variable value |
| `''${var}` | Escaped, passed to shell | Shell runtime | Shell expands `${var}` |
| `$var` | Shell variable | Shell runtime | Shell expands `$var` |

### Examples

```nix
let
  nixVar = "from-nix";
in
mkShell {
  shellHook = ''
    # Nix interpolation - evaluated at Nix eval time
    echo "${nixVar}"              # prints: from-nix

    # Escaped - shell sees ${SHELL_VAR} at runtime
    echo "''${SHELL_VAR:-default}" # prints: value of SHELL_VAR or "default"

    # Simple shell var - shell expands at runtime
    echo "$HOME"                   # prints: /home/username

    # Nix store path interpolation
    echo "${pkgs.hello}/bin/hello" # prints: /nix/store/.../bin/hello
  '';
}
```

### Common Patterns

```nix
shellHook = ''
  # Set with default if not already set (shell-level conditional)
  export GOPATH="''${GOPATH:-$HOME/go}"

  # Append to existing PATH
  export PATH="$GOBIN:''${PATH}"

  # Conditional append to LD_LIBRARY_PATH
  export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
'';
```

---

## Variable Precedence

### Order of Operations

1. **env attribute** variables are exported first (by Nix)
2. **shellHook** executes second (in the shell)
3. If same variable set in both, **shellHook wins** (it runs later)

### Implications

```nix
mkShell {
  env = {
    MY_VAR = "from-env";  # Set first
  };
  shellHook = ''
    export MY_VAR="from-hook"  # Overwrites! This value persists
  '';
}
# Result: MY_VAR="from-hook"
```

### Anti-Pattern (What We Were Doing Wrong)

```nix
# DON'T DO THIS - causes duplication
mkShell {
  env = {
    UV_SYSTEM_PYTHON = "1";  # Set here
  };
  shellHook = ''
    export UV_SYSTEM_PYTHON="1"  # AND here - redundant!
  '';
}
```

---

## Setup Hooks

### Location in Nixpkgs

Setup hooks are in `pkgs/build-support/setup-hooks/`:
- `add-bin-to-path.sh` - adds `$out/bin` to PATH
- `patch-shebangs.sh` - fixes script interpreters
- `make-wrapper.sh` - wrapper script utilities
- `strip.sh` - strips debug symbols

### Creating Custom Setup Hooks

```nix
mySetupHook = pkgs.makeSetupHook {
  name = "my-setup-hook";
  propagatedBuildInputs = [ ];
  substitutions = {
    myVar = "some-value";
  };
} ./my-setup-hook.sh;
```

Where `my-setup-hook.sh`:
```bash
# This script is sourced by downstream dependencies
export MY_CUSTOM_VAR="@myVar@"
```

### Important Note

Setup hooks are sourced as shell scripts, so any `export` statements WILL appear in `env` output. They don't provide a way to "hide" environment variables.

---

## Available Hook Points

### In mkShell

| Hook | When Executed | Use Case |
|------|---------------|----------|
| `shellHook` | On shell entry | Primary setup |

### In stdenv (Build Phases)

These are for package building, not interactive shells:

| Hook | Phase |
|------|-------|
| `preHook` | Before anything |
| `postHook` | After setup |
| `preBuild` | Before build |
| `postBuild` | After build |
| `preInstall` | Before install |
| `postInstall` | After install |
| `preFixup` | Before fixup |
| `postFixup` | After fixup |

### Python-Specific

Python packages have additional hooks:
- `preShellHook` - Before main shellHook
- `postShellHook` - After main shellHook

---

## Path Construction Helpers

### Available Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `lib.makeBinPath` | Construct PATH from packages | `lib.makeBinPath [ pkgs.git pkgs.curl ]` |
| `lib.makeLibraryPath` | Construct LD_LIBRARY_PATH | `lib.makeLibraryPath [ pkgs.openssl ]` |
| `lib.makeSearchPath` | Generic search path | `lib.makeSearchPath "lib" [ pkgs.foo ]` |
| `lib.makeSearchPathOutput` | Search path with output | `lib.makeSearchPathOutput "lib" "lib" [ pkgs.foo ]` |

### Usage in env vs shellHook

**In env attribute** (static, Nix-evaluated):
```nix
env = {
  # Good - fully determined at Nix eval time
  LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.openssl pkgs.zlib ];
};
```

**In shellHook** (dynamic, needs runtime append):
```nix
shellHook = ''
  # Append to existing LD_LIBRARY_PATH at runtime
  export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.openssl ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
'';
```

---

## mkShell Variants

### pkgs.mkShell

- Uses `stdenv` as base
- Includes C compiler (gcc/clang)
- Full build environment

### pkgs.mkShellNoCC

- Uses `stdenvNoCC` as base
- NO C compiler included
- Lighter weight for non-C development

```nix
# Use mkShellNoCC when you don't need C compilation
pkgs.mkShellNoCC {
  packages = [ pkgs.nodejs pkgs.python3 ];
}
```

---

## Wrapper Patterns

### makeWrapper / makeShellWrapper

Creates wrapper scripts for executables with modified environment:

```nix
pkgs.writeShellApplication {
  name = "my-wrapped-tool";
  runtimeInputs = [ pkgs.sometool ];
  text = ''
    exec sometool "$@"
  '';
}

# Or using makeWrapper directly
postInstall = ''
  wrapProgram $out/bin/mytool \
    --set MY_VAR "value" \
    --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}
'';
```

**Note**: Wrappers set env for specific commands, not the entire shell session.

### makeBinaryWrapper

More efficient than makeShellWrapper - uses compiled wrapper instead of shell script.

---

## Best Practices

### 1. Choose One Location Per Variable

```nix
# GOOD - static value in env only
env = { UV_SYSTEM_PYTHON = "1"; };

# BAD - same variable in both places
env = { UV_SYSTEM_PYTHON = "1"; };
shellHook = ''export UV_SYSTEM_PYTHON="1"'';  # Redundant!
```

### 2. Use env for Static, shellHook for Dynamic

```nix
mkShell {
  env = {
    # Static values
    NODE_ENV = "development";
    RUST_BACKTRACE = "1";
    # Nix paths (evaluated at Nix time)
    MY_TOOL_PATH = "${pkgs.mytool}/bin";
  };

  shellHook = ''
    # Dynamic values needing shell expansion
    export GOPATH="''${GOPATH:-$HOME/go}"
    export PATH="$GOPATH/bin:$PATH"
  '';
}
```

### 3. Clean Up shellHook Variable

Add at the end of shellHook to remove it from env output:

```nix
shellHook = ''
  # ... your setup ...

  # Clean up - safe, nothing depends on this after execution
  unset shellHook
'';
```

### 4. Use Proper Escaping

```nix
shellHook = ''
  # Shell variable with default - use ''${ }
  export MYVAR="''${MYVAR:-default}"

  # Nix path interpolation - use ${ }
  export TOOL="${pkgs.sometool}/bin/tool"

  # Conditional append pattern
  export PATH="${pkgs.foo}/bin"''${PATH:+:$PATH}
'';
```

### 5. Modularize Complex Hooks

```nix
let
  pythonHook = ''
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi
  '';

  goHook = ''
    export GOPATH="''${GOPATH:-$HOME/go}"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin"
  '';
in
mkShell {
  shellHook = ''
    ${pythonHook}
    ${goHook}
    unset shellHook
  '';
}
```

### 6. Use inputsFrom for Inheritance

```nix
mkShell {
  inputsFrom = [ myOtherPackage ];  # Inherits env and shellHook
  # Add additional setup
}
```

---

## Implementation Patterns

### Pattern 1: Static Configuration

```nix
mkShell {
  env = {
    # Flags and static config
    UV_SYSTEM_PYTHON = "1";
    PYTHONDONTWRITEBYTECODE = "1";
    NODE_ENV = "development";
    RUST_BACKTRACE = "1";

    # Nix store paths
    KONDUCTOR_SSH_CONFIG = "${./config/ssh.conf}";
    ATUIN_CONFIG_DIR = "${./config/atuin}";
  };
}
```

### Pattern 2: Dynamic User Directories

```nix
mkShell {
  shellHook = ''
    # These need $HOME which isn't available at Nix eval time
    export GOPATH="''${GOPATH:-$HOME/go}"
    export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    export PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"

    # Create directories
    mkdir -p "$GOPATH/bin" "$CARGO_HOME" "$PNPM_HOME"
  '';
}
```

### Pattern 3: PATH Manipulation

```nix
mkShell {
  env = {
    # Static PATH additions via Nix
    # (packages attribute is preferred for this)
  };

  packages = [ pkgs.go pkgs.nodejs ];  # Automatically added to PATH

  shellHook = ''
    # Dynamic PATH additions depending on shell vars
    export PATH="$GOPATH/bin:$CARGO_HOME/bin:$PNPM_HOME:$PATH"
  '';
}
```

### Pattern 4: Conditional Library Path

```nix
mkShell {
  shellHook = ''
    # Nix paths + conditional append to existing
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.openssl
      pkgs.zlib
    ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '';
}
```

### Pattern 5: Shell Hierarchy with overrideAttrs

```nix
# base.nix
mkShell {
  name = "base";
  env = {
    BASE_VAR = "1";
  };
  shellHook = ''
    echo "Base shell"
  '';
}

# full.nix
baseShell.overrideAttrs (old: {
  name = "full";

  # Merge env attributes
  env = old.env // {
    FULL_VAR = "1";
  };

  # Append to shellHook
  shellHook = old.shellHook + ''
    echo "Full shell additions"

    # Clean up at the very end
    unset shellHook
  '';
})
```

---

## Files Requiring Fixes

### Config Files

- [ ] `k9/src/config/shell/ssh.nix` - Line 48: duplicate `export KONDUCTOR_SSH_CONFIG` (already in env line 74)
- [ ] `k9/src/config/shell/atuin.nix` - Line 51: duplicate `export ATUIN_CONFIG_DIR` (already in env line 79); Line 52: move `BASH_PREEXEC_PATH` to env
- [ ] `k9/src/programs/tmux/default.nix` - Line 342: move `export KONDUCTOR_TMUX_CONF` to env attribute

### Devshell Files

- [ ] `k9/src/devshells/base.nix` - Lines 25-26: move `KONDUCTOR_SHELL` and `name` to env (in env.nix)
- [ ] `k9/src/devshells/python.nix` - Lines 24-25: remove duplicate UV_SYSTEM_PYTHON/PYTHONDONTWRITEBYTECODE exports; Lines 20-21: move KONDUCTOR_SHELL/name to env; add `unset shellHook`
- [ ] `k9/src/devshells/go.nix` - Lines 20-21: move KONDUCTOR_SHELL/name to env; add `unset shellHook`
- [ ] `k9/src/devshells/node.nix` - Lines 20-21: move KONDUCTOR_SHELL/name to env; add `unset shellHook`
- [ ] `k9/src/devshells/rust.nix` - Lines 20-21: move KONDUCTOR_SHELL/name to env; add `unset shellHook`
- [ ] `k9/src/devshells/dev.nix` - Lines 24-25: move KONDUCTOR_SHELL/name to env; add `unset shellHook`
- [ ] `k9/src/devshells/full.nix` - Lines 44-45: move KONDUCTOR_SHELL/name to env; Lines 69-70: remove duplicate UV_SYSTEM_PYTHON/PYTHONDONTWRITEBYTECODE; add `unset shellHook`
- [ ] `k9/src/devshells/konductor.nix` - Lines 71-72: move KONDUCTOR_SHELL/name to env; Lines 87-88: remove duplicate UV_SYSTEM_PYTHON/PYTHONDONTWRITEBYTECODE; Line 108: move DOCKER_BUILDKIT to env; add `unset shellHook`
- [ ] `k9/src/devshells/ci.nix` - Lines 56-58: move KONDUCTOR_SHELL/name/CI to env; Lines 64-65: remove duplicate UV_SYSTEM_PYTHON/PYTHONDONTWRITEBYTECODE; Line 85: move DOCKER_BUILDKIT to env; add `unset shellHook`

### Summary of Changes Per File

| File | Remove from shellHook | Add to env | Add unset |
|------|----------------------|------------|-----------|
| ssh.nix | `export KONDUCTOR_SSH_CONFIG=...` | (already there) | no |
| atuin.nix | `export ATUIN_CONFIG_DIR=...` | `BASH_PREEXEC_PATH` | no |
| tmux/default.nix | `export KONDUCTOR_TMUX_CONF=...` | `KONDUCTOR_TMUX_CONF` | no |
| base.nix | `export KONDUCTOR_SHELL/name` | add to env.nix | yes |
| python.nix | UV_SYSTEM_PYTHON, PYTHONDONTWRITEBYTECODE, KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| go.nix | KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| node.nix | KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| rust.nix | KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| dev.nix | KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| full.nix | UV_SYSTEM_PYTHON, PYTHONDONTWRITEBYTECODE, KONDUCTOR_SHELL, name | KONDUCTOR_SHELL, name | yes |
| konductor.nix | UV_SYSTEM_PYTHON, PYTHONDONTWRITEBYTECODE, KONDUCTOR_SHELL, name, DOCKER_BUILDKIT | KONDUCTOR_SHELL, name, DOCKER_BUILDKIT | yes |
| ci.nix | UV_SYSTEM_PYTHON, PYTHONDONTWRITEBYTECODE, KONDUCTOR_SHELL, name, CI, DOCKER_BUILDKIT | KONDUCTOR_SHELL, name, DOCKER_BUILDKIT (CI already there) | yes |

---

## The Konductor Fix

### Before (Problematic)

```nix
# full.nix
baseShell.overrideAttrs (old: {
  env = old.env // {
    UV_SYSTEM_PYTHON = "1";           # Set here
    PYTHONDONTWRITEBYTECODE = "1";    # Set here
  };

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="full"
    export UV_SYSTEM_PYTHON="1"       # AND here - duplicate!
    export PYTHONDONTWRITEBYTECODE="1" # AND here - duplicate!
    export GOPATH="''${GOPATH:-$HOME/go}"
    export PATH="$GOBIN:$PATH"
  '';
})
```

### After (Correct)

```nix
# full.nix
baseShell.overrideAttrs (old: {
  env = old.env // {
    # Static values ONLY in env
    KONDUCTOR_SHELL = "full";
    UV_SYSTEM_PYTHON = "1";
    PYTHONDONTWRITEBYTECODE = "1";
    GO111MODULE = "on";
    CGO_ENABLED = "1";
    NODE_ENV = "development";
    RUST_BACKTRACE = "1";
  };

  shellHook = old.shellHook + ''
    # Dynamic values ONLY in shellHook (need shell expansion)
    export GOPATH="''${GOPATH:-$HOME/go}"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"

    export PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"

    export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"

    # PATH manipulation (depends on above vars)
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    # Conditional activation
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi

    # Clean up shellHook from env output
    unset shellHook
  '';
})
```

### Summary of Changes

1. **Move static values to env attribute**: `KONDUCTOR_SHELL`, `UV_SYSTEM_PYTHON`, `PYTHONDONTWRITEBYTECODE`, etc.
2. **Keep only dynamic values in shellHook**: Anything needing `$HOME`, `${VAR:-default}`, or conditional logic
3. **Add `unset shellHook`** at the end to clean env output
4. **Remove all redundant exports** from shellHook for vars already in env

---

## References

- Nixpkgs mkShell: `pkgs/build-support/mkshell/default.nix`
- Setup hooks: `pkgs/build-support/setup-hooks/`
- stdenv setup: `pkgs/stdenv/generic/setup.sh`
- Nix manual on string interpolation
- DeepWiki research on NixOS/nixpkgs

---

## Document History

- **Created**: 2026-01-21
- **Context**: Debugging environment variable duplication in Konductor devshells
- **Research Method**: DeepWiki queries to NixOS/nixpkgs repository
