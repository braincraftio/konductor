# Flake Input Management & Airgap Build Lifecycle

How Konductor ships fully offline-reproducible QCOW2 images without committing
1GB of vendored sources to git.

## Contents

- [Problem](#problem)
- [Architecture](#architecture)
- [Dual-Mode Operation](#dual-mode-operation)
- [Vendoring Lifecycle](#vendoring-lifecycle)
- [QCOW2 Self-Replication](#qcow2-self-replication)
- [Intermittent Network Update Path](#intermittent-network-update-path)
- [Failure Modes & Recovery](#failure-modes--recovery)
- [Implementation Reference](#implementation-reference)

---

## Problem

Nix flakes in git repos only evaluate git-tracked files. When `flake.nix` uses
`path:./_sources/foo` as an input and `_sources/` is in `.gitignore`, nix copies
the repo to `/nix/store` *without* `_sources/`, and the path resolution fails:

```
error: getting status of '/nix/store/...-source/_sources/catppuccin': No such file or directory
```

We need ~1GB of vendored flake inputs for offline builds, but:

- **Cannot commit** 1GB to git (bloats repo, slow clones)
- **Cannot use git LFS** (adds infrastructure dependency, breaks airgap)
- **Must ship** vendored sources inside the QCOW2 for self-replication
- **Must support** intermittent network access (online refresh → offline rebuild)

---

## Architecture

The solution uses three complementary mechanisms:

```
┌─────────────────────────────────────────────────────────────────────┐
│  flake.nix                                                         │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";   │  │
│  │  inputs.catppuccin.url = "github:catppuccin/nix";            │  │
│  │  ...                                                          │  │
│  └───────────────────────────────────────────────────────────────┘  │
│  Canonical github: URLs — works on any machine with internet       │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
              flake.lock pins exact rev + narHash
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐
  │ Nix Store   │  │ Vendored    │  │ --override-input  │
  │ (primary)   │  │ Directory   │  │ (fallback)        │
  │             │  │ (backup)    │  │                   │
  │ Hydrated by │  │             │  │ Generated from    │
  │ nix flake   │  │ Filesystem  │  │ vendored dir      │
  │ archive     │  │ copy at     │  │ when store cache  │
  │             │  │ /opt/...    │  │ is missing        │
  │ GC-rooted   │  │ /vendored/  │  │                   │
  │ for persist │  │ /sources/   │  │ Bypasses git      │
  │             │  │             │  │ tracking entirely │
  │ Fast builds │  │ Survives GC │  │                   │
  └─────────────┘  └─────────────┘  └──────────────────┘
```

### Why three mechanisms?

| Mechanism | Speed | Survives GC | Survives store wipe | Needs git tracking |
|---|---|---|---|---|
| Nix store (archive) | Fast | With GC roots | No | No |
| Vendored directory | Medium | Yes | Yes | No |
| `--override-input` | Medium | N/A | N/A | No |

The nix store is the fast path. The vendored directory is the durable fallback.
`--override-input` is the recovery mechanism when the store cache is lost.

---

## Dual-Mode Operation

### Online Mode (developer workstation, CI)

```bash
# flake.nix uses github: URLs
# nix fetches inputs from GitHub, caches in store
nix develop .#full
nix build .#qcow2
```

No vendoring required. The flake works like any standard nix flake.

### Offline Mode (airgapped VM, field deployment)

```bash
# All inputs pre-cached in nix store via nix flake archive
# Vendored sources at /opt/konductor/vendored/sources/ as fallback
nix build --offline --no-update-lock-file .#qcow2

# Or via the rebuild helper (tries store first, falls back to overrides)
/opt/konductor/bin/konductor-rebuild
```

No network access required. Everything resolves from local cache.

---

## Vendoring Lifecycle

### Phase 1: Vendor on Build Host (online)

```
Build Host (internet access)
│
├─ nix flake archive .
│  └─ Copies all input source trees to local /nix/store
│     (narHash in flake.lock → deterministic store paths)
│
├─ _sources/ directory (local, gitignored)
│  ├─ nixpkgs/          (~800MB)
│  ├─ nixpkgs-unstable/
│  ├─ catppuccin/
│  ├─ home-manager/
│  ├─ nixvim/
│  ├─ ... (15 inputs)
│  └─ Total: ~1GB
│
└─ flake.lock
   └─ Pinned rev + narHash for every input
```

The `oci:vendor:inputs` task:
1. Reads `flake.lock` to extract locked input references
2. Uses `nix flake prefetch` to download each input to the store
3. Copies store paths to `_sources/` via rsync (for VM transfer)
4. Does NOT modify `flake.nix` (keeps `github:` URLs)
5. Does NOT require `_sources/` to be git-tracked

### Phase 2: Transfer to VM (build pipeline)

```
Build Host                          Build VM
│                                   │
├─ git bundle → scp →──────────────→ /opt/konductor/src/
│  (flake source + history)         │  ├─ flake.nix (github: URLs)
│                                   │  └─ flake.lock (pinned)
│                                   │
├─ rsync _sources/ →───────────────→ /opt/konductor/vendored/sources/
│  (vendored input trees)           │  ├─ nixpkgs/
│                                   │  ├─ catppuccin/
│                                   │  └─ ...
│                                   │
├─ nix flake archive ──────────────→ VM nix store
│  --to ssh://vm                    │  (all input store paths)
│  (hydrates VM store)              │
│                                   │
└─ nix copy ───────────────────────→ VM nix store
   (system closure + devshells)     │  (all build outputs)
                                    │
                                    ├─ GC roots created
                                    │  /var/nix/gcroots/konductor/
                                    │
                                    └─ Ready for offline builds
```

### Phase 3: Seal and Ship

The QCOW2 is sealed with:

| Location | Contents | Purpose |
|---|---|---|
| `/opt/konductor/src/` | Flake source + flake.lock | Build instructions |
| `/opt/konductor/vendored/sources/` | Input source trees (~1GB) | Durable fallback |
| `/nix/store/` | Archived input store paths | Fast offline builds |
| `/var/nix/gcroots/konductor/` | GC root symlinks | Prevent store cleanup |
| `/.konductor` | Provenance attestation | Supply chain audit |

---

## QCOW2 Self-Replication

A deployed QCOW2 VM can rebuild itself into a new QCOW2:

```
Deployed VM (offline)
│
├─ /opt/konductor/src/flake.nix     (github: URLs, doesn't matter offline)
├─ /opt/konductor/src/flake.lock    (pinned narHash → store path lookup)
├─ /nix/store/...                   (archived inputs, GC-rooted)
├─ /opt/konductor/vendored/sources/ (fallback if store purged)
│
└─ nix build --offline --no-update-lock-file .#qcow2
   │
   ├─ Nix resolves inputs from store via narHash ✓
   ├─ Nix builds system closure from cached store paths ✓
   ├─ New QCOW2 contains same /opt/konductor/ layout ✓
   └─ New QCOW2 can also self-replicate ✓
```

### How offline resolution works

1. `flake.lock` contains `narHash` for each input (e.g., `sha256-z5NJP...`)
2. `narHash` deterministically maps to a store path (`/nix/store/<hash>-source`)
3. `--offline` tells nix: "don't fetch, use what's in the store"
4. If the store path exists → input resolved, no network needed
5. If the store path is missing → fallback to `--override-input` from vendored dir

### Rebuild helper: `/opt/konductor/bin/konductor-rebuild`

```bash
#!/usr/bin/env bash
# Try offline store cache first (fast).
# Fall back to --override-input from vendored sources if store cache is missing.
set -euo pipefail

FLAKE_DIR="/opt/konductor/src"
VENDOR_DIR="/opt/konductor/vendored/sources"

# Attempt 1: Pure offline build (inputs in nix store)
echo "Attempting offline build from store cache..."
if nix build --offline --no-update-lock-file "${FLAKE_DIR}#qcow2" 2>/dev/null; then
    echo "✓ Built from store cache"
    exit 0
fi

# Attempt 2: Override inputs from vendored directory
echo "Store cache miss. Falling back to vendored sources..."
if [ ! -d "$VENDOR_DIR" ]; then
    echo "✗ No vendored sources at $VENDOR_DIR"
    echo "  Connect to network and run: konductor-update"
    exit 1
fi

OVERRIDES=()
for input_dir in "$VENDOR_DIR"/*/; do
    name=$(basename "$input_dir")
    if [ -f "${input_dir}flake.nix" ] || [ -f "${input_dir}flake.lock" ]; then
        OVERRIDES+=(--override-input "$name" "path:${input_dir}")
    else
        # Non-flake inputs (e.g., forgejo-runner-src)
        OVERRIDES+=(--override-input "$name" "path:${input_dir}")
    fi
done

nix build --offline "${OVERRIDES[@]}" "${FLAKE_DIR}#qcow2"
echo "✓ Built from vendored sources"
```

---

## Intermittent Network Update Path

When the VM has temporary network access:

```
VM connects to network
│
├─ cd /opt/konductor/src
│
├─ git pull origin main
│  └─ Gets latest flake.nix + flake.lock + source changes
│
├─ nix flake update
│  └─ Refreshes flake.lock with latest input revisions
│
├─ nix flake archive .
│  └─ Downloads new input source trees to nix store
│
├─ konductor-vendor-refresh
│  └─ Updates /opt/konductor/vendored/sources/ from store
│     (extracts archived store paths to filesystem)
│
├─ nix-store --add-root ... (refresh GC roots)
│
└─ Network disconnects — VM is now self-sufficient again
   with updated sources
```

### Update helper: `/opt/konductor/bin/konductor-update`

```bash
#!/usr/bin/env bash
# Online refresh: pull latest, vendor, re-hydrate store.
set -euo pipefail

FLAKE_DIR="/opt/konductor/src"
VENDOR_DIR="/opt/konductor/vendored/sources"
GC_ROOT_DIR="/var/nix/gcroots/konductor"

cd "$FLAKE_DIR"

# Pull latest source
echo "Pulling latest..."
git pull origin main || echo "  (offline or no remote — skipping)"

# Update lock file (requires network for new inputs)
echo "Updating flake.lock..."
nix flake update || echo "  (offline — using existing lock)"

# Archive all inputs to local store
echo "Archiving flake inputs to store..."
ARCHIVE_JSON=$(nix flake archive --json .)

# Create GC roots to prevent garbage collection
echo "Creating GC roots..."
sudo mkdir -p "$GC_ROOT_DIR"
echo "$ARCHIVE_JSON" | jq -r '.. | objects | .path? // empty' | sort -u | \
while read -r store_path; do
    root_name=$(basename "$store_path")
    sudo nix-store --add-root "${GC_ROOT_DIR}/${root_name}" -r "$store_path" >/dev/null
done

# Refresh vendored directory from store
echo "Refreshing vendored sources..."
sudo rm -rf "$VENDOR_DIR"
sudo mkdir -p "$VENDOR_DIR"

jq -r 'to_entries[] | select(.key != "path") | "\(.key)\t\(.value.path)"' \
    <<<"$ARCHIVE_JSON" | while IFS=$'\t' read -r name store_path; do
    [ -n "$store_path" ] && [ -d "$store_path" ] || continue
    sudo rsync -a --chmod=Du+w,Fu+w "$store_path/" "${VENDOR_DIR}/${name}/"
done

sudo chown -R root:root "$VENDOR_DIR"
sudo chmod -R a+rX "$VENDOR_DIR"

echo "✓ Update complete. Offline builds ready."
```

---

## Failure Modes & Recovery

### 1. Store cache evicted by garbage collection

**Symptom**: `nix build --offline` fails with "path not found in store"

**Recovery**: `konductor-rebuild` automatically falls back to `--override-input`
from `/opt/konductor/vendored/sources/`. To restore store cache:

```bash
# Re-archive from vendored sources (no network needed)
for dir in /opt/konductor/vendored/sources/*/; do
    nix store add-path "$dir"
done
nix flake archive --offline .
```

### 2. Vendored directory deleted

**Symptom**: Both store cache and vendored dir missing

**Recovery**: Requires network access.

```bash
konductor-update   # pulls, archives, vendors
```

### 3. flake.lock out of sync after git pull

**Symptom**: `narHash` mismatch errors

**Recovery**:

```bash
# Online: re-lock and re-archive
nix flake lock
nix flake archive .
konductor-update

# Offline: use vendored sources with --override-input (bypasses lock)
konductor-rebuild   # automatic fallback
```

### 4. GitHub rate limiting during initial archive

**Symptom**: 403 errors during `nix flake archive`

**Recovery**: Set `GITHUB_TOKEN` or use the `oci:vendor:inputs` runme task
which uses `nix flake prefetch` with retries:

```bash
export GITHUB_TOKEN="ghp_..."
nix flake archive .
```

### 5. New input added to flake.nix but not vendored

**Symptom**: Offline build fails for one specific input

**Recovery**:

```bash
# Online: re-vendor everything
konductor-update

# Or vendor just the missing input
nix flake prefetch github:owner/repo/rev
```

---

## Implementation Reference

### Files involved

| File | Role |
|---|---|
| `flake.nix` | Canonical `github:` input URLs |
| `flake.lock` | Pinned `rev` + `narHash` for reproducibility |
| `.gitignore` | Excludes `_sources/` from git |
| `docs/developer_guide/qcow2/OCI.md` | `oci:vendor:inputs` task |
| `docs/developer_guide/qcow2/OCI.md` | `_oci:vm:sync` task |

### Nix commands reference

| Command | Purpose | Network |
|---|---|---|
| `nix flake archive .` | Copy all input source trees to local store | Required |
| `nix flake archive --to ssh://vm .` | Copy archived inputs to remote store | Local only |
| `nix flake archive --offline .` | Re-archive from local cache | No |
| `nix build --offline .#qcow2` | Build using only local store | No |
| `nix build --override-input X path:/dir .#qcow2` | Build with local path override | No |
| `nix flake prefetch github:owner/repo/rev` | Fetch single input to store | Required |
| `nix-store --add-root /path -r /nix/store/...` | Create GC root | No |
| `nix flake update` | Refresh flake.lock from upstream | Required |

### Key nix flags

| Flag | Effect |
|---|---|
| `--offline` | Disable network; resolve from local store only |
| `--no-update-lock-file` | Don't try to update flake.lock |
| `--no-write-lock-file` | Don't write changes to flake.lock |
| `--override-input name url` | Replace input with local path (implies `--no-write-lock-file`) |

### QCOW2 filesystem layout

```
/
├── .konductor                              # Provenance attestation
├── opt/konductor/
│   ├── src/                                # Flake source (git history preserved)
│   │   ├── flake.nix                       #   github: URLs (canonical)
│   │   ├── flake.lock                      #   Pinned rev + narHash
│   │   └── src/...                         #   Nix expressions
│   ├── vendored/
│   │   └── sources/                        # Vendored input trees (~1GB)
│   │       ├── nixpkgs/
│   │       ├── catppuccin/
│   │       ├── home-manager/
│   │       ├── nixvim/
│   │       └── ...
│   ├── bin/
│   │   ├── konductor-rebuild               # Offline build (store → fallback)
│   │   └── konductor-update                # Online refresh (pull → archive → vendor)
│   └── k9-<commit>.bundle                  # Git bundle (portable repo)
├── nix/store/
│   └── ...                                 # Archived input store paths
└── var/nix/gcroots/konductor/
    └── ...                                 # GC roots protecting inputs
```
