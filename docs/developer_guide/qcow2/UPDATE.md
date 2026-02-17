---
cwd: ../../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: target:qcow2,scope:vm
runme:
  version: v3
---

# Konductor VM Live Update

Update a running Konductor VM with changes from the k9 repository.

## Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Troubleshooting](#troubleshooting)

---

## Overview

Konductor VMs can be updated in-place using `nixos-rebuild switch` without rebuilding the full QCOW2 image.
This is useful for rapid iteration during development.

### Key Concepts

| Concept | Description |
| ------- | ----------- |
| Vendored inputs | Flake inputs stored in `_sources/` for offline builds |
| `--override-input` | Redirects flake inputs from github to local vendored paths |
| `path:.` reference | Forces nix to use working directory (includes gitignored files) |

### Architecture

The flake.nix uses github inputs for remote compatibility (`github:braincraftio/konductor`).
For offline/airgapped builds, vendored inputs in `_sources/` are used via `--override-input` flags.

```
flake.nix (github inputs) + --override-input → _sources/* (vendored)
```

---

## Quick Start

```bash
# On the VM: pull latest changes
cd /opt/konductor/src
git pull

# Vendor flake inputs (populates _sources/)
runme run oci:vendor:inputs

# Rebuild with vendored inputs
runme run --filename docs/developer_guide/qcow2/UPDATE.md update:rebuild
```

---

## Task Reference

```text
Entry Points:
  update:quick           Pull, vendor, rebuild (one command)
  update:rebuild         Rebuild NixOS configuration
  update:status          Show current system generation
  update:diff            Show changes between current and pending
```

---

## update:quick

Pull latest changes and rebuild in one command.

```sh {"name":"update:quick","excludeFromRunAll":"true","tag":"type:entry"}
set -e

echo "Pulling latest changes..."
git pull || { echo "Pull failed - resolve conflicts first"; exit 1; }

echo ""
echo "Vendoring flake inputs..."
runme run --filename docs/developer_guide/qcow2/OCI.md oci:vendor:inputs

echo ""
echo "Rebuilding NixOS configuration..."
runme run --filename docs/developer_guide/qcow2/UPDATE.md update:rebuild
```

---

## update:rebuild

Rebuild NixOS configuration with vendored inputs.

```sh {"name":"update:rebuild","excludeFromRunAll":"true","tag":"type:entry"}
set -e

# Verify _sources exists
if [ ! -d "_sources" ] || [ ! -f "_sources/nixpkgs/flake.nix" ]; then
    echo "Error: _sources not populated. Run: runme run oci:vendor:inputs"
    exit 1
fi

# Generate --override-input flags from _sources/ contents
# This redirects github inputs in flake.nix to local vendored paths
OVERRIDE_INPUTS=""
for dir in _sources/*/; do
    input=$(basename "$dir")
    OVERRIDE_INPUTS="$OVERRIDE_INPUTS --override-input $input path:./_sources/$input"
done

echo "Rebuilding NixOS configuration..."
echo "  Flake: path:.#konductor"
echo "  Vendored inputs: $(ls -1 _sources | wc -l)"
echo ""

# path:. includes gitignored _sources/
# --no-write-lock-file preserves committed github refs
sudo nixos-rebuild switch --flake 'path:.#konductor' --no-write-lock-file $OVERRIDE_INPUTS

echo ""
echo "Current system generation:"
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5
```

---

## update:status

Show current system generation and provenance.

```sh {"name":"update:status","excludeFromRunAll":"true","tag":"type:entry"}
echo "=== System Generations ==="
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10

echo ""
echo "=== Current Generation ==="
readlink /nix/var/nix/profiles/system

echo ""
echo "=== Provenance ==="
[ -f /.konductor ] && cat /.konductor || echo "(no /.konductor file)"
```

---

## update:diff

Show what would change in a rebuild (dry-run).

```sh {"name":"update:diff","excludeFromRunAll":"true","tag":"type:entry"}
set -e

if [ ! -d "_sources" ]; then
    echo "Error: _sources not populated. Run: runme run oci:vendor:inputs"
    exit 1
fi

# Generate --override-input flags from _sources/ contents
OVERRIDE_INPUTS=""
for dir in _sources/*/; do
    input=$(basename "$dir")
    OVERRIDE_INPUTS="$OVERRIDE_INPUTS --override-input $input path:./_sources/$input"
done

echo "Building new configuration (dry-run)..."
NEW_SYSTEM=$(nix build --no-link --print-out-paths --no-write-lock-file $OVERRIDE_INPUTS 'path:.#nixosConfigurations.konductor.config.system.build.toplevel')
CURRENT_SYSTEM=$(readlink /nix/var/nix/profiles/system)

echo ""
echo "Current: $CURRENT_SYSTEM"
echo "New:     $NEW_SYSTEM"
echo ""

if [ "$NEW_SYSTEM" = "$CURRENT_SYSTEM" ]; then
    echo "No changes - systems are identical"
else
    echo "=== Changes ==="
    nix store diff-closures "$CURRENT_SYSTEM" "$NEW_SYSTEM" 2>/dev/null || \
        echo "(nix store diff-closures not available)"
fi
```

---

## Troubleshooting

### Error: _sources not populated

**Cause:** Vendor task not run or failed.

**Solution:**
```bash
runme run oci:vendor:inputs
```

### Error: cannot pull with rebase: You have unstaged changes

**Cause:** Local modifications to tracked files.

**Solution:**
```bash
git stash
git pull
git stash pop
```

### Services fail after rebuild

Check service status:
```bash
systemctl --failed
journalctl -u konductor-vscode@username -n 50
```

Common issues:
- **nftables syntax error:** Quote escaping issue in firewall rules
- **EnvironmentFile not found:** PKI service ordering issue
- **Certificate not found:** PKI services not started

---
