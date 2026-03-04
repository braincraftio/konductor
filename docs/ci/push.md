---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: scope:ci
runme:
  version: v3
---

# Push to Registry

Push built containerDisk to local registry with multi-tag (git commit, nix derivation, latest).

## Contents

- [push:image](#pushimage) — Multi-tag push to local registry

---

## push:image

Push container with multi-tag (git commit, nix derivation, latest).

**Tags applied:**

- `latest-qcow2` - Convenience tag (always latest)
- `qcow2-<git-commit>` - Source traceability (only if tree is clean)
- `qcow2-<nix-drv>` - Reproducible build ID

**Prerequisites:** Container image built (`build:all`), registry trust configured

```sh {"name":"push:image","excludeFromRunAll":"true","tag":"type:entry,requires:docker"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
BASE_TAG="${CONTAINER_TAG:-latest-qcow2}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"

[ -f .konductor ] || { echo "Error: .konductor not found"; exit 1; }

# Read provenance
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

# Push with all tags
FULL_IMAGE="$REGISTRY/$IMAGE:$BASE_TAG"
docker image inspect "$FULL_IMAGE" &>/dev/null || { echo "Error: $FULL_IMAGE not found"; exit 1; }

for tag in "${TAGS[@]}"; do
    docker tag "$FULL_IMAGE" "$REGISTRY/$IMAGE:$tag"
    skopeo copy --dest-cert-dir "$CERT_DIR" \
        docker-daemon:"$REGISTRY/$IMAGE:$tag" \
        docker://"$REGISTRY/$IMAGE:$tag"
done

# Get digest and update .konductor
OCI_DIGEST=$(skopeo inspect --cert-dir "$CERT_DIR" docker://"$FULL_IMAGE" | jq -r '.Digest')
cat >> .konductor << EOF
oci_digest = "$OCI_DIGEST"
EOF

echo "Pushed: $REGISTRY/$IMAGE"
printf "  %s\n" "${TAGS[@]}"
echo "Digest: $OCI_DIGEST"
```
