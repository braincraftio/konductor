---
cwd: /opt/konductor
shell: bash
skipPrompts: true
tag: k9:ci:qcow2:verify,k9:ci:qcow2:verify:qcow2
runme:
  version: v3
---

# Konductor Build Verification

Verify this Konductor VM can reproduce its own build from `/.konductor` provenance.

**Execution context:** This file runs INSIDE a built Konductor VM (`cwd: /opt/konductor`),
not on the build host.

## Contents

- [Quick Verify](#quick-verify)
- [Verification Tasks](#verification-tasks)
- [Full Reproduction](#full-reproduction)

---

## Quick Verify

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  verify:help                     Show this help                             │
│    ├── :provenance               Display /.konductor                        │
│    ├── :source                   Verify git commit matches                  │
│    ├── :flake                    Verify flake.lock hash                     │
│    ├── :nix                      Verify nix derivation hash                 │
│    ├── :all                      Run all verification checks                │
│    └── :reproduce                Full reproduction build (slow)             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### verify:help

```sh {"name":"k9:ci:qcow2:verify:help","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
cat << 'EOF'
verify — Konductor Build Verification

Usage: runme run --filename docs/ci/verify.md verify:<task>

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

### verify:provenance

Display provenance from `/.konductor`.

```sh {"name":"k9:ci:qcow2:verify:provenance","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
[ -f /.konductor ] || { echo "Error: /.konductor not found (not a Konductor VM?)"; exit 1; }
cat /.konductor
```

---

### verify:source

Verify git commit matches provenance.

```sh {"name":"k9:ci:qcow2:verify:git-commit","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
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

### verify:flake

Verify flake.lock sha256 matches provenance.

```sh {"name":"k9:ci:qcow2:verify:flake","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
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

### verify:nix

Verify nix derivation hash matches provenance.

```sh {"name":"k9:ci:qcow2:verify:nix","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
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

### verify:all

Run all verification checks.

```sh {"name":"k9:ci:qcow2:verify:all","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
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

### verify:reproduce

Full reproduction build — builds QCOW2 and compares image_sha256.

```sh {"name":"k9:ci:qcow2:verify:reproduce","excludeFromRunAll":"true","tag":"k9:ci:qcow2:verify"}
set -e
echo "=== Full Reproduction Build ==="
echo "This will build a new QCOW2 and compare sha256"
echo ""

[ -f /.konductor ] || { echo "Error: /.konductor not found"; exit 1; }

EXPECTED_SHA=$(sed -n 's/^image_sha256 = "\(.*\)"$/\1/p' /.konductor)
echo "Expected image_sha256: $EXPECTED_SHA"
echo ""

# Run verification first
runme run k9:ci:qcow2:verify:all

echo ""
echo "=== Starting Build ==="
echo "This may take 30+ minutes..."
echo ""

# Build using the image-only pipeline (no container packaging needed for reproduction)
runme run --all --tag=k9:ci:pipeline:image --filename docs/ci/build.md

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
