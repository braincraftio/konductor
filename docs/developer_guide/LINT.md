---
cwd: ../..
shell: bash
skipPrompts: true
tag: target:lint,target:fmt,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor Lint & Format

Code quality tools for linting and formatting.

## Contents

- [Quick Start](#quick-start)
- [Lint Tasks](#lint-tasks)
- [Format Tasks](#format-tasks)

---

## Quick Start

| Task | Description |
|------|-------------|
| `lint` | Run all linters |
| `lint:nix` | Lint Nix files (statix, deadnix) |
| `lint:bash` | Lint shell scripts (shellcheck) |
| `lint:yaml` | Lint YAML (yamllint) |
| `lint:toml` | Lint TOML (taplo) |
| `lint:actions` | Lint GitHub Actions (actionlint) |
| `fmt` | Format all files |
| `fmt:nix` | Format Nix (nixpkgs-fmt) |
| `fmt:bash` | Format shell (shfmt) |
| `fmt:toml` | Format TOML (taplo) |
| `fmt:check` | Check formatting (no changes) |

---

## Lint Tasks

### lint

Run all linters.

```sh {"name":"lint","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint All ==="
echo ""
FAILED=0

printf "%-12s" "nix:"
if runme run lint:nix 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

printf "%-12s" "bash:"
if runme run lint:bash 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

printf "%-12s" "toml:"
if runme run lint:toml 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

echo ""
if [ $FAILED -gt 0 ]; then
    echo "Lint failed"
    exit 1
fi
echo "All linters passed"
```

`runme run lint`

---

### lint:nix

Lint Nix files with statix and deadnix.

```sh {"name":"lint:nix","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint Nix ==="
echo ""

echo "Running statix..."
statix check .

echo ""
echo "Running deadnix..."
deadnix --fail .

echo ""
echo "Nix lint passed"
```

`runme run lint:nix`

---

### lint:bash

Lint shell scripts with shellcheck.

```sh {"name":"lint:bash","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint Shell ==="
echo ""

# Find shell files
SHELL_FILES=$(find . -type f \( -name '*.sh' -o -name '*.bash' \) \
    -not -path './.git/*' \
    -not -path './result/*' \
    -not -path './.direnv/*' \
    2>/dev/null || true)

if [ -z "$SHELL_FILES" ]; then
    echo "No shell files found"
    exit 0
fi

echo "Checking: $(echo "$SHELL_FILES" | wc -l | tr -d ' ') files"
echo "$SHELL_FILES" | xargs shellcheck -x

echo ""
echo "Shell lint passed"
```

`runme run lint:bash`

---

### lint:yaml

Lint YAML files with yamllint.

```sh {"name":"lint:yaml","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint YAML ==="
echo ""
yamllint .
echo "YAML lint passed"
```

`runme run lint:yaml`

---

### lint:toml

Lint TOML files with taplo.

```sh {"name":"lint:toml","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint TOML ==="
echo ""
taplo lint
echo "TOML lint passed"
```

`runme run lint:toml`

---

### lint:actions

Lint GitHub Actions workflows with actionlint.

```sh {"name":"lint:actions","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Lint GitHub Actions ==="
echo ""

if [ ! -d .github/workflows ]; then
    echo "No .github/workflows directory"
    exit 0
fi

actionlint
echo "Actions lint passed"
```

`runme run lint:actions`

---

## Format Tasks

### fmt

Format all files.

```sh {"name":"fmt","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Format All ==="
echo ""

echo "Formatting Nix..."
nixpkgs-fmt .

echo "Formatting TOML..."
taplo fmt

echo "Formatting shell..."
find .config/mise/lib -name '*.sh' -exec shfmt -w -i 4 -ci -sr {} + 2>/dev/null || true

echo ""
echo "Format complete"
```

`runme run fmt`

---

### fmt:nix

Format Nix files with nixpkgs-fmt.

```sh {"name":"fmt:nix","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Format Nix ==="
nixpkgs-fmt .
echo "Done"
```

`runme run fmt:nix`

---

### fmt:bash

Format shell scripts with shfmt.

```sh {"name":"fmt:bash","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Format Shell ==="

# shfmt options: -i 4 (indent), -ci (case indent), -sr (redirect space)
find . -type f \( -name '*.sh' -o -name '*.bash' \) \
    -not -path './.git/*' \
    -not -path './result/*' \
    -not -path './.direnv/*' \
    -exec shfmt -w -i 4 -ci -sr {} + 2>/dev/null || true

echo "Done"
```

`runme run fmt:bash`

---

### fmt:toml

Format TOML files with taplo.

```sh {"name":"fmt:toml","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Format TOML ==="
taplo fmt
echo "Done"
```

`runme run fmt:toml`

---

### fmt:check

Check formatting without making changes.

```sh {"name":"fmt:check","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Format Check ==="
echo ""
FAILED=0

printf "%-12s" "nix:"
if nixpkgs-fmt --check . 2>/dev/null; then
    echo "OK"
else
    echo "NEEDS FORMAT"
    FAILED=1
fi

printf "%-12s" "toml:"
if taplo fmt --check 2>/dev/null; then
    echo "OK"
else
    echo "NEEDS FORMAT"
    FAILED=1
fi

echo ""
if [ $FAILED -gt 0 ]; then
    echo "Run: runme run fmt"
    exit 1
fi
echo "All files formatted correctly"
```

`runme run fmt:check`
