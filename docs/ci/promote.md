---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:qcow2:promote
runme:
  version: v3
---

# Promote to Production Registry

Copy validated image to the production cluster registry (`$PROMOTE_REGISTRY`).

## Contents

- [promote:image](#promoteimage) — Copy to production registry with all tags

---

## promote:image

Promote validated image from docker daemon to the production cluster registry.

**What it does:**

1. Reads build-time image name from `.konductor` provenance
2. Verifies source image exists in local Docker daemon
3. Copies image with all tags to `$PROMOTE_REGISTRY` via skopeo
4. Verifies copy with digest check

**Environment variables:**

- `PROMOTE_REGISTRY` - Destination registry (e.g. `registry.ucs.central01.helix.cisco.com`)
- `PROMOTE_IMAGE` - Destination image name (default: `projv-engprod/konductor`)
- `CONTAINER_TAG` - Base tag (default: `latest-qcow2`)

**Prerequisites:** Image validated (`validate:deploy` passed), registry trust configured

**Duration:** 2-5 minutes

```bash {"name":"k9:ci:qcow2:promote","excludeFromRunAll":"true","tag":"k9:ci:qcow2:promote,k9:ci:qcow2,type:entry,duration:slow"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  promote:image — Promote to Production Registry"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

[[ "${WORKSPACE_ROOT:-}" == /* ]] || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

[ -f .konductor ] || { echo "✗ Provenance file .konductor not found"; exit 1; }

DST_REGISTRY="${PROMOTE_REGISTRY:?PROMOTE_REGISTRY must be set}"
IMAGE="${PROMOTE_IMAGE:-projv-engprod/konductor}"
BASE_TAG="${CONTAINER_TAG:-latest-qcow2}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/${DST_REGISTRY}"

# Read build-time image name from provenance
SRC_IMAGE=$(sed -n 's/^oci_image = "\(.*\)"$/\1/p' .konductor)
[ -n "$SRC_IMAGE" ] || { echo "✗ oci_image not found in .konductor"; exit 1; }
SRC_FULL="${SRC_IMAGE}:${BASE_TAG}"
docker image inspect "$SRC_FULL" &>/dev/null || { echo "✗ $SRC_FULL not found in docker daemon"; exit 1; }

echo "Source: docker-daemon:${SRC_FULL}"
echo "Destination: ${DST_REGISTRY}/${IMAGE}"
echo ""

# Read provenance for tags
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

TAGS=("$BASE_TAG")
[ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && TAGS+=("qcow2-${git_commit}")
[ -n "$nix_drv" ] && TAGS+=("qcow2-${nix_drv}")

echo "Promoting with tags:"
printf "  %s\n" "${TAGS[@]}"
echo ""

_failed=0
for tag in "${TAGS[@]}"; do
    echo "▶ ${DST_REGISTRY}/${IMAGE}:${tag}"
    if ! skopeo copy \
        --dest-cert-dir "$CERT_DIR" \
        --dest-authfile "${WORKSPACE_ROOT}/.docker/config.json" \
        docker-daemon:"$SRC_FULL" \
        docker://"$DST_REGISTRY/$IMAGE:$tag"; then
        echo "FAIL: Failed to copy tag: $tag"
        _failed=$((_failed + 1))
    fi
done
[ "$_failed" -eq 0 ] || { echo "FAIL: $_failed tag(s) failed to promote"; exit 1; }

echo ""
echo "✓ Promoted to ${DST_REGISTRY}/${IMAGE}"
skopeo inspect --cert-dir "$CERT_DIR" docker://"$DST_REGISTRY/$IMAGE:$BASE_TAG" | jq '{Digest, Created}'
```
