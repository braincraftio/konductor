---
cwd: ../../..
shell: bash
skipPrompts: true
tag: target:nix,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor Nix Flake Operations

Manage Nix flake inputs, builds, store maintenance, and binary cache.

## Contents

- [Output](#output)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Flake Operations](#flake-operations)
- [Store Maintenance](#store-maintenance)
- [Binary Cache](#binary-cache)
- [Registry Management](#registry-management)
- [Diagnostics](#diagnostics)

---

## Output

| Command | Result |
|---------|--------|
| `nix:update` | Updated `flake.lock` with latest input versions |
| `nix:build` | Build output in `./result` symlink |
| `nix:check` | Flake validation (CI exit 0/1) |
| `nix:gc` | Freed disk space in `/nix/store` |
| `nix:cache:push` | Build outputs uploaded to Cachix |

---

## Prerequisites

| Tool | Purpose | Check |
|------|---------|-------|
| Nix/Lix | Package manager | `nix --version` |
| Flakes | Experimental feature | `nix show-config \| grep flakes` |
| Cachix | Binary cache (optional) | `cachix --version` |

All tools provided by `nix develop .#full`.

---

## Quick Start

| Task | Description |
|------|-------------|
| `nix` | Show this help |
| `nix:update` | Update all flake inputs |
| `nix:update:input` | Update specific input |
| `nix:build` | Build flake output |
| `nix:check` | Validate flake (CI-friendly) |
| `nix:show` | Show flake outputs and metadata |
| `nix:gc` | Garbage collect store |
| `nix:gc:aggressive` | Aggressive GC (all generations) |
| `nix:optimise` | Deduplicate store |
| `nix:info` | Show Nix installation info |
| `nix:doctor` | Run health diagnostics |
| `nix:cache:push` | Push to Cachix |
| `nix:registry:add` | Add to flake registry |
| `nix:registry:list` | List registries |

### nix

Show available tasks.

```sh {"name":"nix","excludeFromRunAll":"true","tag":"type:entry"}
cat << 'EOF'
nix - Konductor Nix Flake Operations

Usage: runme run nix:<task>

Flake Operations:
  :update           Update all flake inputs (flake.lock)
  :update:input     Update specific input (e.g., nixpkgs)
  :build            Build flake output
  :check            Validate flake configuration (CI)
  :show             Show flake outputs and metadata

Store Maintenance:
  :gc               Garbage collect nix store
  :gc:aggressive    Aggressive GC (removes all old generations)
  :optimise         Deduplicate store paths

Binary Cache:
  :cache:push       Push build outputs to Cachix

Registry:
  :registry:add     Add konductor to flake registry
  :registry:list    List configured registries
  :registry:remove  Remove from registry

Diagnostics:
  :info             Show Nix installation info
  :doctor           Run health diagnostics

Examples:
  runme run nix:update                  # Update all inputs
  runme run nix:update:input nixpkgs    # Update just nixpkgs
  runme run nix:build .#qcow2           # Build specific output
  runme run nix:check                   # Validate flake (CI)
  runme run nix:gc                      # Free disk space

Related:
  runme run setup:verify                # Check prerequisites
  runme run build:qcow2:image           # Build VM image
EOF
```

`runme run nix`

---

## Task Reference

| Category | Task | Description |
|----------|------|-------------|
| **Flake** | `nix:update` | Update all inputs |
| | `nix:update:input` | Update specific input |
| | `nix:build` | Build output |
| | `nix:check` | Validate (CI) |
| | `nix:show` | Show metadata |
| **Store** | `nix:gc` | Garbage collect |
| | `nix:gc:aggressive` | Aggressive GC |
| | `nix:optimise` | Deduplicate |
| **Cache** | `nix:cache:push` | Push to Cachix |
| **Registry** | `nix:registry:add` | Add entry |
| | `nix:registry:list` | List registries |
| | `nix:registry:remove` | Remove entry |
| **Diag** | `nix:info` | Installation info |
| | `nix:doctor` | Health check |

---

## Flake Operations

### nix:update

Update all flake inputs to latest versions.

```sh {"name":"nix:update","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Update Flake Inputs ==="
echo ""
nix flake update
echo ""
echo "Updated flake.lock"
echo "Review changes: git diff flake.lock"
```

`runme run nix:update`

---

### nix:update:input

Update a specific flake input.

```sh {"name":"nix:update:input","excludeFromRunAll":"true","tag":"type:entry"}
set -e
INPUT="${1:-}"
if [ -z "$INPUT" ]; then
    echo "Usage: runme run nix:update:input <input-name>"
    echo ""
    echo "Available inputs:"
    nix flake metadata --json 2>/dev/null | jq -r '.locks.nodes | keys[]' | grep -v root | sort | sed 's/^/  /'
    exit 1
fi
echo "Updating input: $INPUT"
nix flake lock --update-input "$INPUT"
echo "Done. Review: git diff flake.lock"
```

`runme run nix:update:input nixpkgs`

---

### nix:build

Build a flake output.

```sh {"name":"nix:build","excludeFromRunAll":"true","tag":"type:entry"}
set -e
OUTPUT="${1:-.#default}"
echo "=== Nix Build ==="
echo "Output: $OUTPUT"
echo ""
nix build "$OUTPUT" --no-warn-dirty
echo ""
if [ -L result ]; then
    echo "Result: $(readlink result)"
    ls -la result/
fi
```

`runme run nix:build .#qcow2`

---

### nix:check

Validate flake configuration. CI-friendly (exits 1 on failure).

```sh {"name":"nix:check","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Flake Check ==="
echo ""
# Check current system only (--all-systems fails on cross-platform packages like qcow2)
nix flake check
echo ""
echo "Flake is valid"
```

`runme run nix:check`

---

### nix:show

Show flake outputs and metadata.

```sh {"name":"nix:show","excludeFromRunAll":"true","tag":"type:entry","interactive":"false"}
set -e
echo "=== Flake Outputs ==="
echo ""
nix flake show
echo ""
echo "=== Flake Metadata ==="
echo ""
nix flake metadata
```

`runme run nix:show`

---

## Store Maintenance

### nix:gc

Garbage collect Nix store. Removes unreferenced store paths.

```sh {"name":"nix:gc","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Garbage Collection ==="
echo ""

echo "Store size before:"
du -sh /nix/store 2>/dev/null || echo "  (cannot read store size)"
echo ""

echo "Running garbage collection..."
nix-collect-garbage

echo ""
echo "Store size after:"
du -sh /nix/store 2>/dev/null || echo "  (cannot read store size)"
```

`runme run nix:gc`

---

### nix:gc:aggressive

Aggressive garbage collection. Removes ALL old generations.

```sh {"name":"nix:gc:aggressive","excludeFromRunAll":"true","tag":"type:entry,type:destructive"}
set -e
echo "=== Aggressive Garbage Collection ==="
echo ""
echo "WARNING: This removes ALL old generations!"
echo "You will not be able to rollback to previous configurations."
echo ""

echo "Store size before:"
du -sh /nix/store 2>/dev/null || echo "  (cannot read store size)"
echo ""

echo "Deleting old generations..."
nix-collect-garbage -d

echo ""
echo "Store size after:"
du -sh /nix/store 2>/dev/null || echo "  (cannot read store size)"
```

`runme run nix:gc:aggressive`

---

### nix:optimise

Optimise Nix store by deduplicating identical files.

```sh {"name":"nix:optimise","excludeFromRunAll":"true","tag":"type:entry,duration:slow"}
set -e
echo "=== Store Optimisation ==="
echo ""
echo "Deduplicating store paths (this may take a while)..."
nix-store --optimise
echo ""
echo "Optimisation complete"
```

`runme run nix:optimise`

---

## Binary Cache

### nix:cache:push

Push build outputs to Cachix. Requires `CACHIX_AUTH_TOKEN`.

```sh {"name":"nix:cache:push","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
: ${CACHIX_NAME:=braincraftio}

echo "=== Push to Cachix ==="
echo "Cache: $CACHIX_NAME"
echo ""

if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
    echo "Error: CACHIX_AUTH_TOKEN not set"
    echo ""
    echo "Get token from: https://app.cachix.org/cache/$CACHIX_NAME/settings"
    echo "Set with: export CACHIX_AUTH_TOKEN=..."
    exit 1
fi

if [ ! -L result ]; then
    echo "Error: No result symlink. Run nix:build first."
    exit 1
fi

echo "Pushing result to cache..."
cachix push "$CACHIX_NAME" result

echo ""
echo "Pushed to: https://$CACHIX_NAME.cachix.org"
```

`CACHIX_AUTH_TOKEN=xxx runme run nix:cache:push`

---

## Registry Management

### nix:registry:add

Add konductor to local flake registry for convenient access.

```sh {"name":"nix:registry:add","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Add Flake Registry Entry ==="
echo ""

if nix registry list 2>/dev/null | grep -q "flake:konductor"; then
    echo "Already registered:"
    nix registry list | grep konductor
else
    nix registry add konductor github:braincraftio/konductor
    echo "Added: konductor -> github:braincraftio/konductor"
fi

echo ""
echo "Usage:"
echo "  nix develop konductor#full"
echo "  nix build konductor#qcow2"
echo "  nix run konductor#nvim"
```

`runme run nix:registry:add`

---

### nix:registry:list

List configured flake registries.

```sh {"name":"nix:registry:list","excludeFromRunAll":"true","tag":"type:entry","interactive":"false"}
echo "=== Flake Registries ==="
echo ""
nix registry list
```

`runme run nix:registry:list`

---

### nix:registry:remove

Remove konductor from local flake registry.

```sh {"name":"nix:registry:remove","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Remove Registry Entry ==="
echo ""

if nix registry list 2>/dev/null | grep -q "flake:konductor"; then
    nix registry remove konductor
    echo "Removed: konductor"
else
    echo "Not registered: konductor"
fi
```

`runme run nix:registry:remove`

---

## Diagnostics

### nix:info

Show Nix installation information.

```sh {"name":"nix:info","excludeFromRunAll":"true","tag":"type:entry","interactive":"false"}
echo "=== Nix Installation ==="
echo ""

printf "%-16s" "Version:"
nix --version 2>/dev/null | head -1 || echo "not installed"

printf "%-16s" "Store:"
du -sh /nix/store 2>/dev/null | cut -f1 || echo "unknown"

printf "%-16s" "Daemon:"
if systemctl is-active nix-daemon >/dev/null 2>&1; then
    echo "running (systemd)"
elif pgrep -x nix-daemon >/dev/null 2>&1; then
    echo "running"
else
    echo "not running"
fi

printf "%-16s" "Flakes:"
if nix show-config 2>/dev/null | grep -q "experimental-features.*flakes"; then
    echo "enabled"
else
    echo "disabled"
fi

printf "%-16s" "System:"
nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || echo "unknown"
echo ""

echo ""
echo "=== Substituters ==="
nix show-config 2>/dev/null | grep "^substituters" | sed 's/substituters = //' | tr ' ' '\n' | sed 's/^/  /'
```

`runme run nix:info`

---

### nix:doctor

Run comprehensive Nix health diagnostics.

```sh {"name":"nix:doctor","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Nix Health Diagnostics ==="
echo ""

ERRORS=0
WARNINGS=0

# Nix installed
printf "%-20s" "Nix installed:"
if command -v nix >/dev/null 2>&1; then
    echo "OK ($(nix --version 2>/dev/null | head -1 | sed 's/.*) //'))"
else
    echo "MISSING"
    ERRORS=$((ERRORS + 1))
fi

# Daemon running
printf "%-20s" "Daemon:"
if [ "$(uname -s)" = "Darwin" ]; then
    echo "OK (macOS)"
elif systemctl is-active nix-daemon >/dev/null 2>&1; then
    echo "OK (systemd)"
elif pgrep -x nix-daemon >/dev/null 2>&1; then
    echo "OK (running)"
else
    echo "NOT RUNNING"
    ERRORS=$((ERRORS + 1))
fi

# Flakes enabled
printf "%-20s" "Flakes:"
if nix show-config 2>/dev/null | grep -q "experimental-features.*flakes"; then
    echo "OK"
else
    echo "DISABLED"
    ERRORS=$((ERRORS + 1))
fi

# flake.nix exists
printf "%-20s" "flake.nix:"
if [ -f flake.nix ]; then
    echo "OK"
else
    echo "MISSING"
    ERRORS=$((ERRORS + 1))
fi

# flake.lock exists
printf "%-20s" "flake.lock:"
if [ -f flake.lock ]; then
    LOCK_AGE=$(( ($(date +%s) - $(stat -c %Y flake.lock 2>/dev/null || stat -f %m flake.lock 2>/dev/null || echo 0)) / 86400 ))
    if [ "$LOCK_AGE" -gt 30 ]; then
        echo "OLD (${LOCK_AGE}d ago)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo "OK (${LOCK_AGE}d ago)"
    fi
else
    echo "MISSING"
    WARNINGS=$((WARNINGS + 1))
fi

# Flake evaluates
printf "%-20s" "Flake evaluates:"
if nix flake show >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    ERRORS=$((ERRORS + 1))
fi

# Store space
printf "%-20s" "Store space:"
STORE_SIZE=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "unknown")
echo "$STORE_SIZE"

echo ""
echo "─────────────────────────────────"
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS error(s), $WARNINGS warning(s)"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo "OK: $WARNINGS warning(s)"
else
    echo "OK: All checks passed"
fi
```

`runme run nix:doctor`
