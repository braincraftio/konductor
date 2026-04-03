---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: k9:ci:qcow2:validate
runme:
  version: v3
---

# Validation

Deploy VM to KubeVirt, validate SSH, services, and Forgejo runner workflow.

## Contents

- [validate:deploy](#validatedeploy) — Deploy + SSH test
- [validate:services](#validateservices) — Web terminal health checks
- [validate:runner](#validaterunner) — Forgejo runner workflow test

---

## validate:deploy

Deploy VM to KubeVirt and validate SSH access.

**What it does:**

1. Deploys VM to `konductor` namespace via Pulumi (`mise run dev:k8s:konductor:up`)
2. Waits for VM to boot and SSH to be available
3. Verifies provenance file `/.konductor` exists
4. Runs basic validation commands

**Prerequisites:** Cluster running, image pushed to registry

**Duration:** 3-5 minutes

```bash {"name":"k9:ci:qcow2:validate:deploy","excludeFromRunAll":"true","tag":"k9:ci:qcow2:validate,k9:ci:pipeline:all,type:entry,requires:k8s,duration:slow"}
set -e
mise run dev:k8s:konductor:up
mise run dev:k8s:konductor:validate
```

---

## validate:services

Test web terminal services via port-forward (non-blocking).

**Services tested:**

- `ttyd` (port 7681) - xterm.js terminal (readonly)
- `ghostty-web` (port 7682) - ghostty WASM terminal (readonly)
- `ttyd-rw` (port 7683) - xterm.js terminal (writable)
- `ghostty-web-rw` (port 7684) - ghostty WASM terminal (writable)

**Note:** This check is non-blocking. Failures generate warnings but don't fail the pipeline. Services may still be starting.

**Prerequisites:** VM deployed to KubeVirt (`validate:deploy`)

```bash {"name":"k9:ci:qcow2:validate:services","excludeFromRunAll":"true","tag":"k9:ci:qcow2:validate,k9:ci:pipeline:all,type:entry,requires:k8s"}
set -eo pipefail

pkill -f "virtctl port-forward.*konductor" 2>/dev/null || true

cleanup() {
    pkill -f "virtctl port-forward.*konductor" 2>/dev/null || true
}
trap cleanup EXIT

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  validate:services — Web Terminal Health Check"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Services:"
echo "    ttyd readonly     (7681) - xterm.js terminal"
echo "    ghostty-web readonly (7682) - ghostty WASM terminal"
echo "    ttyd writable     (7683) - xterm.js terminal (rw)"
echo "    ghostty-web writable (7684) - ghostty WASM terminal (rw)"
echo ""
echo "  Note: This check is non-blocking. Failures are warnings only."
echo ""

NAMESPACE="konductor"
VMI="vmi/konductor"
WARNINGS=0

SERVICES=(
    "ttyd:7681:<!DOCTYPE html>"
    "ghostty-web:7682:<!DOCTYPE html>"
    "ttyd-rw:7683:<!DOCTYPE html>"
    "ghostty-web-rw:7684:<!DOCTYPE html>"
)

for svc in "${SERVICES[@]}"; do
    IFS=':' read -r name port expected <<< "$svc"
    echo "▶ Testing ${name} (port ${port})..."

    virtctl port-forward --namespace="$NAMESPACE" "$VMI" "${port}:${port}" &
    PF_PID=$!
    sleep 2

    if curl -sf --max-time 5 "http://localhost:${port}/" 2>/dev/null | grep -q "$expected"; then
        echo "  ✓ ${name}: responding with expected content"
    else
        echo "  ⚠ ${name}: not responding or unexpected content"
        ((WARNINGS++)) || true
    fi

    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
done

echo ""
if [ "$WARNINGS" -eq 0 ]; then
    echo "✅ All services responding"
else
    echo "⚠ ${WARNINGS} service(s) not responding (non-blocking)"
    echo "  Manual verification:"
    echo "  virtctl port-forward -n konductor vmi/konductor 7681:7681 7682:7682 7683:7683 7684:7684"
fi
```

---

## validate:runner

Test Forgejo runner by pushing to local git server and validating workflow execution.

**What it does:**

1. Provisions Forgejo user and access token
2. Creates repositories: `projv-engprod/k9` (main repo) and `projv-engprod/workspace` (shared tooling)
3. Pushes workspace repository
4. Pushes k9 repository
5. Triggers workflow via API: `validate-environment.yaml`
6. Polls workflow status until completion
7. Verifies success

**Why important:** This validates that:

- Forgejo runner can execute workflows in the VM
- VM has network access to pull dependencies
- Workspace pattern works (runner clones workspace repo first)
- Build environment is functional

**Prerequisites:** Cluster running with Forgejo deployed, VM with runner configured

**Duration:** 5-10 minutes

```bash {"name":"k9:ci:qcow2:validate:runner","excludeFromRunAll":"true","tag":"k9:ci:qcow2:validate,k9:ci:pipeline:all,type:entry,requires:k8s,duration:slow"}
set -eo pipefail

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  validate:runner — Validate Forgejo Runner"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

[[ "${WORKSPACE_ROOT:-}" == /* ]] || { echo "✗ WORKSPACE_ROOT must be absolute"; exit 1; }

export KUBECONFIG="${WORKSPACE_ROOT}/.config/talos/clusters/docker-dev/generated/kubeconfig"
[ -f "$KUBECONFIG" ] || { echo "✗ KUBECONFIG not found"; exit 1; }

FORGEJO_NS="forgejo"
FORGEJO_DEPLOY="deployment/forgejo-deployment"
REPO_NAME="k9"
REPO_OWNER="projv-engprod"
TOKEN_NAME="ci-runner-test-$(date +%s)"
BRANCH="${GITHUB_REF_NAME:-main}"
WORKFLOW="validate-environment.yaml"

echo "▶ Phase 1: Provision Forgejo credentials..."
RUNNER_PASSWORD="${FORGEJO_RUNNER_PASSWORD:-admin123}"

TOKEN_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  forgejo admin user generate-access-token \
    --username "$REPO_OWNER" \
    --token-name "$TOKEN_NAME" \
    --scopes "all" \
    --raw 2>&1) && TOKEN="$TOKEN_OUTPUT" || true

if [ -z "$TOKEN" ]; then
  CREATE_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
    forgejo admin user create \
      --username "$REPO_OWNER" \
      --email "${REPO_OWNER}@localhost" \
      --password "$RUNNER_PASSWORD" \
      --admin \
      --must-change-password=false \
      --access-token \
      --access-token-name "$TOKEN_NAME" \
      --access-token-scopes "all" 2>&1) || true
  TOKEN=$(echo "$CREATE_OUTPUT" | rg -o '[a-f0-9]{40}' | tail -1)

  if [ -z "$TOKEN" ] && echo "$CREATE_OUTPUT" | grep -q "already exists"; then
    RETRY_TOKEN_NAME="${TOKEN_NAME}-$(date +%s)"
    TOKEN_OUTPUT=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
      forgejo admin user generate-access-token \
        --username "$REPO_OWNER" \
        --token-name "$RETRY_TOKEN_NAME" \
        --scopes "all" \
        --raw 2>&1) && TOKEN="$TOKEN_OUTPUT" || true
  fi
fi

[ -n "$TOKEN" ] || { echo "✗ Failed to provision credentials"; exit 1; }
echo "✓ Credentials provisioned"

echo ""
echo "▶ Phase 2: Create repositories..."
kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    --post-data="{\"name\":\"$REPO_NAME\",\"private\":false}" \
    "http://localhost:3000/api/v1/user/repos" 2>&1 || true

kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    --post-data="{\"name\":\"workspace\",\"private\":false}" \
    "http://localhost:3000/api/v1/user/repos" 2>&1 || true

echo ""
echo "▶ Phase 3-4: Push repositories..."
GIT_CA_CERT="${WORKSPACE_ROOT}/.certs/registry.docker.arpa/ca.crt"
[ -f "$GIT_CA_CERT" ] || { echo "✗ CA cert not found"; exit 1; }

git -C .. remote remove runner-test 2>/dev/null || true
git -C .. remote add runner-test "https://${REPO_OWNER}:${TOKEN}@git.docker.arpa/${REPO_OWNER}/workspace.git"
GIT_SSL_CAINFO="$GIT_CA_CERT" git -C .. push --force runner-test "HEAD:refs/heads/$BRANCH" 2>&1 || true
git -C .. remote remove runner-test 2>/dev/null || true

git remote remove runner-test 2>/dev/null || true
git remote add runner-test "https://${REPO_OWNER}:${TOKEN}@git.docker.arpa/${REPO_OWNER}/${REPO_NAME}.git"
GIT_SSL_CAINFO="$GIT_CA_CERT" git push --force runner-test "HEAD:refs/heads/$BRANCH" 2>&1 || true

echo ""
echo "▶ Phase 5: Trigger workflow..."
kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
  wget -qO- --post-data='{"ref":"'"$BRANCH"'"}' \
    --header="Authorization: token $TOKEN" \
    --header="Content-Type: application/json" \
    "http://localhost:3000/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/${WORKFLOW}/dispatches" 2>&1 || true

echo ""
echo "▶ Phase 6: Wait for workflow completion..."
MAX_WAIT=5400
POLL_INTERVAL=5
ELAPSED=0
STATUS="unknown"
sleep 3

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  RUN_JSON=$(kubectl exec -n "$FORGEJO_NS" "$FORGEJO_DEPLOY" -c forgejo -- \
    wget -qO- --header="Authorization: token $TOKEN" \
      "http://localhost:3000/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs" 2>/dev/null) || true

  if [ -n "$RUN_JSON" ]; then
    RUN_LINE=$(echo "$RUN_JSON" | jq -r ".workflow_runs[] | select(.workflow_id == \"$WORKFLOW\") | \"\(.id) \(.status) \(.html_url)\"" | sort -n | tail -1)
    if [ -n "$RUN_LINE" ]; then
      STATUS=$(echo "$RUN_LINE" | cut -d' ' -f2)
      echo "  Status: ${STATUS} (${ELAPSED}s)"
      case "$STATUS" in success|failure|cancelled|skipped) break ;; esac
    fi
  fi
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

git remote remove runner-test 2>/dev/null || true

case "$STATUS" in
  success) echo "✓ Workflow completed successfully" ;;
  *) echo "✗ Workflow failed or timed out"; exit 1 ;;
esac
```
