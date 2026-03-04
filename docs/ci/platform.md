---
cwd: ../..
shell: /run/current-system/sw/bin/bash
skipPrompts: true
tag: scope:ci,scope:cluster
runme:
  version: v3
---

# Platform Management

Talos Kubernetes cluster lifecycle for the Konductor CI pipeline.

## Contents

- [platform:up](#platformup) — Start cluster + deploy platform
- [platform:down](#platformdown) — Destroy cluster
- [platform:status](#platformstatus) — Check cluster health

---

## platform:up

Start Talos Kubernetes cluster in Docker and deploy platform services.

**What it does:**

1. Starts Talos control plane + worker nodes in Docker containers
2. Deploys core platform via Pulumi:
   - Cilium CNI
   - cert-manager (TLS certificate management)
   - Envoy Gateway (ingress)
   - Zot registry (local OCI registry at registry.docker.arpa)
   - KubeVirt (VM orchestration)
   - Forgejo (git server + runner for CI testing)

**Prerequisites:** Docker running, sufficient resources (8GB RAM, 100GB disk)

```sh {"name":"platform:up","excludeFromRunAll":"true","tag":"type:entry,scope:cluster,duration:slow"}
# Clean any existing cluster
mise run dev:k8s:compose:clean

# Start Talos in Docker
mise run dev:k8s:compose:up

# Deploy platform (Cilium, cert-manager, Envoy Gateway, Zot registry, etc.)
mise run dev:k8s:pulumi:up
```

---

## platform:down

Destroy the cluster.

**Warning:** This is destructive. All cluster data will be lost.

```sh {"name":"platform:down","excludeFromRunAll":"true","tag":"type:entry,type:destructive,scope:cluster"}
mise run dev:k8s:compose:clean
```

---

## platform:status

Check cluster and registry status.

```sh {"name":"platform:status","excludeFromRunAll":"true","tag":"type:entry,scope:cluster,type:readonly"}
kubectl get nodes
kubectl get po -n registry
kubectl get httproute -n registry
curl -sk -u admin:admin https://registry.docker.arpa/v2/_catalog | jq
```
