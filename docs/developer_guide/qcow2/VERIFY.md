---
cwd: /opt/konductor
shell: bash
skipPrompts: true
tag: target:qcow2,scope:verify
runme:
  version: v3
---

# Konductor Build Verification

Verify this Konductor VM can reproduce its own build from `/.konductor` provenance.

## Contents

- [Quick Verify](#quick-verify)
- [Verification Tasks](#verification-tasks)
- [Full Reproduction](#full-reproduction)

---

## Quick Verify

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  verify:konductor                Show this help                             │
│    ├── :provenance               Display /.konductor                        │
│    ├── :source                   Verify git commit matches                  │
│    ├── :flake                    Verify flake.lock hash                     │
│    ├── :nix                      Verify nix derivation hash                 │
│    ├── :all                      Run all verification checks                │
│    └── :reproduce                Full reproduction build (slow)             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### verify:konductor

```sh {"name":"verify:konductor","excludeFromRunAll":"true"}
cat << 'EOF'
verify:konductor - Konductor Build Verification

Usage: runme run verify:konductor:<task>

Tasks:
  :provenance    Display /.konductor provenance
  :source        Verify git commit matches
  :flake         Verify flake.lock sha256
  :nix           Verify nix derivation hash
  :all           Run all verification checks
  :reproduce     Full reproduction build

Verification Chain:
  git_commit → flake_lock_sha256 → nix_hash → nix_drv → image_sha256

If nix_drv matches, Nix guarantees reproducible output.
EOF
```

---

## Verification Tasks

### verify:konductor:provenance

Display provenance from `/.konductor`.

```sh {"name":"verify:konductor:provenance","excludeFromRunAll":"true"}
[ -f /.konductor ] || { echo "Error: /.konductor not found (not a Konductor VM?)"; exit 1; }
cat /.konductor
```

---

### verify:konductor:source

Verify git commit matches provenance.

```sh {"name":"verify:konductor:source","excludeFromRunAll":"true"}
set -e
[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }

EXPECTED=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)
ACTUAL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

echo "Expected: $EXPECTED"
echo "Actual:   $ACTUAL"

if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✓ git_commit matches"
else
    echo "✗ git_commit differs"
    exit 1
fi
```

---

### verify:konductor:flake

Verify flake.lock sha256 matches provenance.

```sh {"name":"verify:konductor:flake","excludeFromRunAll":"true"}
set -e
[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }
[ -f flake.lock ] || { echo "Error: flake.lock not found"; exit 1; }

EXPECTED=$(sed -n 's/^flake_lock_sha256 = "\(.*\)"$/\1/p' /.konductor)
ACTUAL=$(sha256sum flake.lock | cut -d' ' -f1)

echo "Expected: $EXPECTED"
echo "Actual:   $ACTUAL"

if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✓ flake_lock_sha256 matches"
else
    echo "✗ flake_lock_sha256 differs"
    exit 1
fi
```

---

### verify:konductor:nix

Verify nix derivation hash matches provenance.

```sh {"name":"verify:konductor:nix","excludeFromRunAll":"true"}
set -e
[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }

EXPECTED_HASH=$(sed -n 's/^nix_hash = "\(.*\)"$/\1/p' /.konductor)
EXPECTED_DRV=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' /.konductor)

ACTUAL_HASH=$(nix flake metadata --json 2>/dev/null | jq -r '.locked.narHash // "unknown"')
ACTUAL_DRV=$(nix path-info --derivation .#qcow2 2>/dev/null | head -1 | xargs basename | cut -d- -f1 || echo "unknown")

echo "=== nix_hash ==="
echo "Expected: $EXPECTED_HASH"
echo "Actual:   $ACTUAL_HASH"
if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
    echo "✓ nix_hash matches"
else
    echo "✗ nix_hash differs"
fi

echo ""
echo "=== nix_drv ==="
echo "Expected: $EXPECTED_DRV"
echo "Actual:   $ACTUAL_DRV"
if [ "$EXPECTED_DRV" = "$ACTUAL_DRV" ]; then
    echo "✓ nix_drv matches (REPRODUCIBLE BUILD)"
else
    echo "✗ nix_drv differs"
    exit 1
fi
```

---

### verify:konductor:all

Run all verification checks.

```sh {"name":"verify:konductor:all","excludeFromRunAll":"true"}
set -e
echo "=== Konductor Build Verification ==="
echo ""

[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }

# Check git_dirty first (trust gate)
GIT_DIRTY=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' /.konductor)
if [ "$GIT_DIRTY" != "0" ]; then
    echo "⚠ WARNING: git_dirty = $GIT_DIRTY"
    echo "  Build was from dirty working tree - cannot fully verify"
    echo ""
fi

ERRORS=0

# Source
EXPECTED=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' /.konductor)
ACTUAL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✓ git_commit"
else
    echo "✗ git_commit: expected $EXPECTED, got $ACTUAL"
    ((ERRORS++))
fi

# Flake lock
if [ -f flake.lock ]; then
    EXPECTED=$(sed -n 's/^flake_lock_sha256 = "\(.*\)"$/\1/p' /.konductor)
    ACTUAL=$(sha256sum flake.lock | cut -d' ' -f1)
    if [ "$EXPECTED" = "$ACTUAL" ]; then
        echo "✓ flake_lock_sha256"
    else
        echo "✗ flake_lock_sha256: expected $EXPECTED, got $ACTUAL"
        ((ERRORS++))
    fi
else
    echo "✗ flake.lock not found"
    ((ERRORS++))
fi

# Nix hash
EXPECTED=$(sed -n 's/^nix_hash = "\(.*\)"$/\1/p' /.konductor)
ACTUAL=$(nix flake metadata --json 2>/dev/null | jq -r '.locked.narHash // "unknown"')
if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✓ nix_hash"
else
    echo "✗ nix_hash: expected $EXPECTED, got $ACTUAL"
    ((ERRORS++))
fi

# Nix drv (the key one)
EXPECTED=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' /.konductor)
ACTUAL=$(nix path-info --derivation .#qcow2 2>/dev/null | head -1 | xargs basename | cut -d- -f1 || echo "unknown")
if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✓ nix_drv (REPRODUCIBLE)"
else
    echo "✗ nix_drv: expected $EXPECTED, got $ACTUAL"
    ((ERRORS++))
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== ALL CHECKS PASSED ==="
    echo "This build can be reproduced from /opt/konductor"
else
    echo "=== $ERRORS CHECK(S) FAILED ==="
    exit 1
fi
```

---

## Full Reproduction

### verify:konductor:reproduce

Full reproduction build - builds QCOW2 and compares image_sha256.

```sh {"name":"verify:konductor:reproduce","excludeFromRunAll":"true"}
set -e
echo "=== Full Reproduction Build ==="
echo "This will build a new QCOW2 and compare sha256"
echo ""

[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }

EXPECTED_SHA=$(sed -n 's/^image_sha256 = "\(.*\)"$/\1/p' /.konductor)
echo "Expected image_sha256: $EXPECTED_SHA"
echo ""

# Run verification first
runme run verify:konductor:all

echo ""
echo "=== Starting Build ==="
echo "This may take 30+ minutes..."
echo ""

# Build using the same process
export QCOW2_BUILD_FILE=docs/developer_guide/qcow2/BUILD.md
runme run --filename "$QCOW2_BUILD_FILE" build:qcow2:image

ACTUAL_SHA=$(sha256sum konductor.qcow2 | cut -d' ' -f1)

echo ""
echo "=== Result ==="
echo "Expected: $EXPECTED_SHA"
echo "Actual:   $ACTUAL_SHA"
echo ""

if [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ]; then
    echo "✓ image_sha256 MATCHES - BIT-FOR-BIT REPRODUCIBLE"
else
    echo "✗ image_sha256 differs"
    echo ""
    echo "Possible causes:"
    echo "  - Timestamps embedded in image"
    echo "  - Non-deterministic VM configuration"
    echo "  - Different tool versions"
    echo ""
    echo "The nix_drv match confirms the Nix build is reproducible."
    echo "Differences are likely in the VM configuration phase."
    exit 1
fi
```

---

## Provenance Fields

| Field | Purpose | Verification |
|-------|---------|--------------|
| `git_commit` | Source code version | `git rev-parse HEAD` |
| `git_dirty` | Trust gate (0 = clean) | Must be 0 for reproducibility |
| `nix_version` | Nix toolchain version | `nix --version` |
| `nix_hash` | Flake inputs hash | `nix flake metadata --json` |
| `nix_drv` | Derivation hash | `nix path-info --derivation .#qcow2` |
| `flake_lock_sha256` | Lock file integrity | `sha256sum flake.lock` |
| `image_sha256` | Final artifact | `sha256sum konductor.qcow2` |
