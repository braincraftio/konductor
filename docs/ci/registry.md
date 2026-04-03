---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:registry
runme:
  version: v3
---

# Registry Operations

Registry trust, authentication, and inspection for the Konductor CI pipeline.

## Contents

- [registry:trust](#registrytrust) — Install cluster CA
- [registry:login](#registrylogin) — Authenticate to registry
- [registry:list](#registrylist) — List images
- [registry:tags](#registrytags) — List tags

---

## registry:trust

Install cluster CA certificate for Docker daemon and Skopeo.

**What it does:**

1. Extracts CA certificate from Envoy Gateway TLS secret
2. Installs to `/etc/docker/certs.d/registry.docker.arpa/ca.crt` (Docker daemon)
3. Installs to `${WORKSPACE_ROOT}/.certs/registry.docker.arpa/ca.crt` (Skopeo)

**Why needed:** `registry.docker.arpa` uses a self-signed CA from cert-manager. Docker and Skopeo need this CA to trust the registry's TLS certificate.

**Prerequisites:** Cluster running, kubectl configured

```bash {"name":"k9:ci:registry:trust","excludeFromRunAll":"true","tag":"k9:ci:registry,k9:ci:pipeline:all,type:entry"}
set -e

[[ "${WORKSPACE_ROOT:-}" == /* ]] && printf "✓ WORKSPACE_ROOT=%s\n" "$WORKSPACE_ROOT" || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

printf "✓ KUBECONFIG=%s\n" "$KUBECONFIG"
[ -f "$KUBECONFIG" ] && printf "✓ KUBECONFIG file exists\n" || { echo "✗ KUBECONFIG file not found"; exit 1; }

REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
K8S_CONTEXT="${KUBECTL_CONTEXT:-admin@docker-dev-host}"

# Docker daemon cert directory
DOCKER_CERT_DIR="/etc/docker/certs.d/$REGISTRY"
sudo mkdir -p "$DOCKER_CERT_DIR"

kubectl --context "$K8S_CONTEXT" \
    get secret gateway-tls-https -n envoy-gateway-system \
    -o jsonpath='{.data.ca\.crt}' | base64 -d \
    | sudo tee "$DOCKER_CERT_DIR/ca.crt" > /dev/null

echo "✓ CA installed: $DOCKER_CERT_DIR/ca.crt"

# Skopeo/Podman cert directory
CONTAINERS_CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"
mkdir -p "$CONTAINERS_CERT_DIR"
kubectl --context "$K8S_CONTEXT" \
    get secret gateway-tls-https -n envoy-gateway-system \
    -o jsonpath='{.data.ca\.crt}' | base64 -d \
    > "$CONTAINERS_CERT_DIR/ca.crt"

echo "✓ CA installed: $CONTAINERS_CERT_DIR/ca.crt"
```

---

## registry:login

Authenticate Docker and Skopeo to registry.

**Credentials:** Default `admin:admin` (configurable via `REGISTRY_USERNAME`/`REGISTRY_PASSWORD`)

```bash {"name":"k9:ci:registry:login","excludeFromRunAll":"true","tag":"k9:ci:registry,k9:ci:pipeline:all,type:entry"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
USERNAME="${REGISTRY_USERNAME:-admin}"
PASSWORD="${REGISTRY_PASSWORD:-admin}"
CERT_DIR="${WORKSPACE_ROOT}/.certs/$REGISTRY"

# Docker login
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

# Skopeo login
echo "$PASSWORD" | skopeo login "$REGISTRY" \
    --username "$USERNAME" --password-stdin \
    --cert-dir "$CERT_DIR" --compat-auth-file ${WORKSPACE_ROOT}/.docker/config.json

echo "✓ Logged in to $REGISTRY"
```

---

## registry:list

List images in registry.

```bash {"name":"k9:ci:registry:list","excludeFromRunAll":"true","tag":"k9:ci:registry,type:entry,type:readonly"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
curl -sk -u "${REGISTRY_USERNAME:-admin}:${REGISTRY_PASSWORD:-admin}" \
    "https://$REGISTRY/v2/_catalog" | jq
```

---

## registry:tags

List tags for konductor image.

```bash {"name":"k9:ci:registry:tags","excludeFromRunAll":"true","tag":"k9:ci:registry,k9:ci:pipeline:all,type:entry,type:readonly"}
set -e
REGISTRY="${CONTAINER_REGISTRY:-registry.docker.arpa}"
IMAGE="${CONTAINER_IMAGE:-projv-engprod/konductor}"
curl -sk -u "${REGISTRY_USERNAME:-admin}:${REGISTRY_PASSWORD:-admin}" \
    "https://$REGISTRY/v2/$IMAGE/tags/list" | jq
```
