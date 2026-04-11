---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:qcow2:push
runme:
  version: v3
---

# Push to Registry

Push built containerDisk to docker-dev local registry with multi-tag (git commit, nix derivation, latest).

## Contents

- [push:image](#pushimage) — Multi-tag push to docker-dev local registry

---

## push:image

Push container with multi-tag (git commit, nix derivation, latest).

**Tags applied:**

- `latest-qcow2` - Convenience tag (always latest)
- `qcow2-<git-commit>` - Source traceability (only if tree is clean)
- `qcow2-<nix-drv>` - Reproducible build ID

**Prerequisites:** Container image built (`build:all`), docker-dev cluster running, registry trust configured

```bash {"name":"k9:ci:qcow2:push:image","excludeFromRunAll":"true","tag":"k9:ci:qcow2:push,k9:ci:pipeline:all,type:entry,requires:docker"}
set -e
REGISTRY="registry.docker.arpa"
IMAGE="${CONTAINER_IMAGE:-projv-engprod/konductor}"
BASE_TAG="${CONTAINER_TAG:-latest-qcow2}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read build-time image name and provenance
SRC_IMAGE=$(sed -n 's/^oci_image = "\(.*\)"$/\1/p' .konductor)
[ -n "$SRC_IMAGE" ] || { echo "Error: oci_image not found in .konductor"; exit 1; }
SRC_FULL="${SRC_IMAGE}:${BASE_TAG}"
docker image inspect "$SRC_FULL" &>/dev/null || { echo "Error: $SRC_FULL not found in docker daemon"; exit 1; }

git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' .konductor)
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' .konductor)
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' .konductor)

# Build tag list
TAGS=("$BASE_TAG")
if [ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && [ "$git_commit" != "unknown" ]; then
    TAGS+=("qcow2-${git_commit}")
fi
if [ -n "$nix_drv" ] && [ "$nix_drv" != "unknown" ]; then
    TAGS+=("qcow2-${nix_drv}")
fi

# Push from docker daemon to docker-dev registry
for tag in "${TAGS[@]}"; do
    echo "▶ ${REGISTRY}/${IMAGE}:${tag}"
    skopeo copy --dest-cert-dir "$CERT_DIR" \
        docker-daemon:"$SRC_FULL" \
        docker://"$REGISTRY/$IMAGE:$tag"
done

# Get digest and update .konductor
OCI_DIGEST=$(skopeo inspect --cert-dir "$CERT_DIR" docker://"$REGISTRY/$IMAGE:$BASE_TAG" | jq -r '.Digest')
cat >> .konductor << EOF
oci_digest = "$OCI_DIGEST"
EOF

echo "Pushed: $REGISTRY/$IMAGE"
printf "  %s\n" "${TAGS[@]}"
echo "Digest: $OCI_DIGEST"
```
