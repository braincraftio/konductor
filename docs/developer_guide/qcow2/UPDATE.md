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
| `path:.` reference | Forces nix to use working directory (includes gitignored files) |
| Git flake | Default behavior copies git-tracked files to store (excludes `_sources/`) |

### Why `path:.`?

The flake uses vendored inputs via `path:./_sources/*` URLs for airgap/offline builds.
Since `_sources/` is in `.gitignore`, when nix evaluates a git flake it copies the repo
to `/nix/store` **without** the `_sources/` directory, causing evaluation to fail.

Using `path:.` tells nix to use the working directory directly, which includes gitignored files.

---

## Quick Start

```bash
# On the VM: pull latest changes
cd /workspace/*/git.braincraft.io/braincraft/k9
git pull

# Vendor flake inputs (populates _sources/)
runme run oci:vendor:inputs || true  # Final nix flake lock may fail, that's OK

# Rebuild with path: reference (includes _sources/)
sudo nixos-rebuild switch --flake 'path:.#konductor'
```

---

## Task Reference

```text
Entry Points:
  update:quick           Pull, vendor, rebuild (one command)
  update:vendor          Vendor flake inputs only
  update:rebuild         Rebuild NixOS configuration

Debug:
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
runme run --filename docs/developer_guide/qcow2/UPDATE.md update:vendor || true

echo ""
echo "Rebuilding NixOS configuration..."
runme run --filename docs/developer_guide/qcow2/UPDATE.md update:rebuild
```

---

## update:vendor

Vendor flake inputs into `_sources/` for offline evaluation.

The final `nix flake lock` step may fail because it tries to evaluate the flake
from a git context (which excludes `_sources/`). This is expected - the inputs
are still vendored successfully.

```sh {"name":"update:vendor","excludeFromRunAll":"true","tag":"type:entry"}
set -euo pipefail

echo "Vendoring flake inputs into ./_sources ..."
sudo -E rm -rf _sources
mkdir -p _sources
sudo -E chown -R "$(id -u):$(id -g)" _sources

export XDG_CACHE_HOME="/tmp/konductor-nix-cache"
export HOME="/tmp/konductor-nix-home"
mkdir -p "$XDG_CACHE_HOME" "$HOME"

# Resolve inputs from flake.lock (works even when flake.nix uses path inputs)
jq -c '
  .nodes as $nodes
  | (.nodes.root.inputs | keys) as $roots
  | ($roots + ["flake-parts","nuschtosSearch","ixx","nixlib","systems"])
  | unique
  | map(select($nodes[.] != null))
  | .[]
  | . as $k
  | {name:$k} + ($nodes[$k])
  | [
      .name,
      .locked.type,
      (.locked.owner // null),
      (.locked.repo // null),
      (.locked.rev // null),
      (.locked.ref // null),
      (.locked.url // null)
    ]
' flake.lock > /tmp/vendor-lock.jsonl

while read -r row; do
  name=$(jq -r '.[0]' <<<"$row")
  typ=$(jq -r '.[1]' <<<"$row")
  owner=$(jq -r '.[2] // empty' <<<"$row")
  repo=$(jq -r '.[3] // empty' <<<"$row")
  rev=$(jq -r '.[4] // empty' <<<"$row")
  url=$(jq -r '.[6] // empty' <<<"$row")
  [ -n "$name" ] || continue
  case "$typ" in
    github) flakeref="github:${owner}/${repo}/${rev}" ;;
    git) flakeref="git+${url}?rev=${rev}" ;;
    *) echo "Skipping: $name ($typ)"; continue ;;
  esac
  echo "  -> $name"
  XDG_CACHE_HOME="$XDG_CACHE_HOME" HOME="$HOME" \
    nix --extra-experimental-features 'nix-command flakes' \
    flake prefetch --no-use-registries --refresh --json "$flakeref" > /tmp/prefetch.json 2>/dev/null || {
      echo "Warning: prefetch failed for $name"
      continue
    }
  store_path=$(jq -r '.storePath' /tmp/prefetch.json)
  [ -d "$store_path" ] && rsync -a --chmod=Du+w,Fu+w "$store_path/" "_sources/$name/"
done < /tmp/vendor-lock.jsonl

rm -f /tmp/vendor-lock.jsonl /tmp/prefetch.json
unset XDG_CACHE_HOME HOME

echo "Vendored inputs into ./_sources"
ls -la _sources/
```

---

## update:rebuild

Rebuild NixOS configuration using path: flake reference.

```sh {"name":"update:rebuild","excludeFromRunAll":"true","tag":"type:entry"}
set -e

# Verify _sources exists
if [ ! -d "_sources" ] || [ ! -f "_sources/nixpkgs/flake.nix" ]; then
    echo "Error: _sources not populated. Run update:vendor first."
    exit 1
fi

echo "Rebuilding NixOS configuration..."
echo "  Flake: path:.#konductor"
echo ""

sudo nixos-rebuild switch --flake 'path:.#konductor'

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
    echo "Error: _sources not populated. Run update:vendor first."
    exit 1
fi

echo "Building new configuration (dry-run)..."
NEW_SYSTEM=$(nix build --no-link --print-out-paths 'path:.#nixosConfigurations.konductor.config.system.build.toplevel')
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

### Error: path '.../_sources/catppuccin/flake.nix' does not exist

**Cause:** Using git flake reference instead of `path:.`

**Solution:** Use `path:.#konductor` not `$(pwd)#konductor`:
```bash
sudo nixos-rebuild switch --flake 'path:.#konductor'
```

### Error: cannot pull with rebase: You have unstaged changes

**Cause:** `runme run oci:vendor:inputs` modified `flake.lock`

**Solution:** Reset flake.lock before pull:
```bash
git checkout flake.lock
git pull
```

### Vendor task exits with error but _sources is populated

**Expected behavior.** The vendor task's final `nix flake lock` step fails because
it tries to evaluate the flake from a git context. The inputs are already vendored
at that point.

**Solution:** Ignore the error and proceed with rebuild:
```bash
runme run oci:vendor:inputs || true
sudo nixos-rebuild switch --flake 'path:.#konductor'
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
