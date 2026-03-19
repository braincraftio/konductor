---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:qcow2:promote
runme:
  version: v3
---

# Promote to Public Registry

Copy validated image to public registry (docker.io or ghcr.io).

## Contents

- [promote:image](#promoteimage) — Copy to public registry with all tags

---

## promote:image

Copy validated image to public registry (docker.io or ghcr.io).

**What it does:**

1. Verifies source image exists in local registry
2. Authenticates to destination registry
3. Copies image with all tags (latest, git commit, nix derivation)
4. Verifies copy with digest check

**Authentication:**

- **docker.io**: Set `DOCKER_TOKEN` environment variable (from Docker Hub)
- **ghcr.io**: Set `GITHUB_TOKEN` environment variable (GitHub PAT with packages:write)

**Environment variables:**

- `PROMOTE_REGISTRY` - Destination registry (default: `docker.io`)
- `PROMOTE_IMAGE` - Destination image (default: `containercraft/konductor`)
- `PROMOTE_TAG` - Base tag (default: `latest-qcow2`)
- `DOCKER_TOKEN` - Docker Hub access token
- `DOCKER_USERNAME` - Docker Hub username (default: `containercraft`)
- `GITHUB_TOKEN` - GitHub personal access token
- `GITHUB_ACTOR` - GitHub username

**Prerequisites:** Image validated (`validate:deploy` passed), credentials configured

**Duration:** 2-5 minutes

```bash {"name":"k9:ci:qcow2:promote","excludeFromRunAll":"true","tag":"k9:ci:qcow2:promote,k9:ci:qcow2,type:entry,duration:slow"}
set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  promote:image — Promote to Public Registry"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

[[ "${WORKSPACE_ROOT:-}" == /* ]] || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

PROVENANCE_FILE="${WORKSPACE_ROOT}/flake/.konductor"
[ -f "$PROVENANCE_FILE" ] || { echo "✗ Provenance file not found"; exit 1; }

SRC_REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
SRC_IMAGE="${CONTAINER_IMAGE:-containercraft/konductor}"
SRC_TAG="${CONTAINER_TAG:-latest-qcow2}"
SRC_CERT_DIR="${WORKSPACE_ROOT}/.certs/${SRC_REGISTRY}"
[ -d "$SRC_CERT_DIR" ] || { echo "✗ Source cert dir not found"; exit 1; }

DST_REGISTRY="${PROMOTE_REGISTRY:-docker.io}"
DST_IMAGE="${PROMOTE_IMAGE:-containercraft/konductor}"
DST_TAG="${PROMOTE_TAG:-latest-qcow2}"

echo "Source: ${SRC_REGISTRY}/${SRC_IMAGE}:${SRC_TAG}"
echo "Destination: ${DST_REGISTRY}/${DST_IMAGE}:${DST_TAG}"
echo ""

# Authentication
AUTH_LOCATIONS=("${WORKSPACE_ROOT}/.docker/config.json" "${HOME}/.docker/config.json")
DEST_AUTH_FILE=""

has_docker_io_creds() {
    [[ -f "$1" ]] && jq -e '.auths["https://index.docker.io/v1/"]' "$1" &>/dev/null
}
has_ghcr_creds() {
    [[ -f "$1" ]] && jq -e '.auths["ghcr.io"]' "$1" &>/dev/null
}

for auth_file in "${AUTH_LOCATIONS[@]}"; do
    [[ ! -f "$auth_file" ]] && continue
    if [[ "$DST_REGISTRY" == "docker.io" ]] && has_docker_io_creds "$auth_file"; then
        DEST_AUTH_FILE="$auth_file"
        break
    elif [[ "$DST_REGISTRY" == "ghcr.io" ]] && has_ghcr_creds "$auth_file"; then
        DEST_AUTH_FILE="$auth_file"
        break
    fi
done

[[ -z "$DEST_AUTH_FILE" ]] && DEST_AUTH_FILE="${WORKSPACE_ROOT}/.docker/config.json"

if [[ "$DST_REGISTRY" == "docker.io" ]]; then
    if [[ -n "${DOCKER_TOKEN:-}" ]]; then
        mkdir -p "$(dirname "$DEST_AUTH_FILE")"
        echo "$DOCKER_TOKEN" | skopeo login docker.io -u "${DOCKER_USERNAME:-containercraft}" --password-stdin --compat-auth-file "$DEST_AUTH_FILE"
        echo "✓ Authenticated to docker.io"
    elif has_docker_io_creds "$DEST_AUTH_FILE"; then
        echo "✓ Using existing docker.io credentials"
    else
        echo "✗ No authentication. Set DOCKER_TOKEN or run: docker login docker.io"
        exit 1
    fi
elif [[ "$DST_REGISTRY" == "ghcr.io" ]]; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        mkdir -p "$(dirname "$DEST_AUTH_FILE")"
        echo "$GITHUB_TOKEN" | skopeo login ghcr.io -u "${GITHUB_ACTOR:-github}" --password-stdin --compat-auth-file "$DEST_AUTH_FILE"
        echo "✓ Authenticated to ghcr.io"
    elif has_ghcr_creds "$DEST_AUTH_FILE"; then
        echo "✓ Using existing ghcr.io credentials"
    else
        echo "✗ No authentication. Set GITHUB_TOKEN or run: docker login ghcr.io"
        exit 1
    fi
fi

# Verify source
skopeo inspect --cert-dir "$SRC_CERT_DIR" docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" &>/dev/null \
    || { echo "✗ Source image not found"; exit 1; }
echo "✓ Source exists"

# Read provenance for tags
git_commit=$(sed -n 's/^git_commit = "\(.*\)"$/\1/p' "$PROVENANCE_FILE")
git_dirty=$(sed -n 's/^git_dirty = \(.*\)$/\1/p' "$PROVENANCE_FILE")
nix_drv=$(sed -n 's/^nix_drv = "\(.*\)"$/\1/p' "$PROVENANCE_FILE")

TAGS=("$DST_TAG")
[ "$git_dirty" = "0" ] && [ -n "$git_commit" ] && TAGS+=("qcow2-${git_commit}")
[ -n "$nix_drv" ] && TAGS+=("qcow2-${nix_drv}")

echo ""
echo "Copying with tags:"
printf "  %s\n" "${TAGS[@]}"
echo ""

_failed=0
for tag in "${TAGS[@]}"; do
    echo "▶ ${DST_REGISTRY}/${DST_IMAGE}:${tag}"
    if ! skopeo copy \
        --src-cert-dir "$SRC_CERT_DIR" \
        --dest-authfile "$DEST_AUTH_FILE" \
        docker://"$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG" \
        docker://"$DST_REGISTRY/$DST_IMAGE:$tag"; then
        echo "FAIL: Failed to copy tag: $tag"
        _failed=$((_failed + 1))
    fi
done
[ "$_failed" -eq 0 ] || { echo "FAIL: $_failed tag(s) failed to promote"; exit 1; }

echo ""
echo "✓ Promoted to ${DST_REGISTRY}/${DST_IMAGE}"
skopeo inspect --no-creds docker://"$DST_REGISTRY/$DST_IMAGE:$DST_TAG" | jq '{Digest, Created}'
```
