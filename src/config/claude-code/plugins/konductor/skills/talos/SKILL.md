---
name: talos
description: Konductor Talos Linux and KubeVirt cluster workflows. Use when working with talosctl, Talos cluster config under .config/talos/, KubeVirt VMs (virtctl), or the docker-dev / optiplex / central01 clusters in the Konductor platform.
---

# Konductor Talos / KubeVirt

Konductor runs workloads on Talos Linux Kubernetes clusters, with KubeVirt for
VM workloads (the konductor qcow2 image runs as a KubeVirt VMI).

## Cluster + config facts

- Cluster configs live under `.config/talos/clusters/<cluster>/generated/`
  (`kubeconfig`, `talosconfig`). `KUBECONFIG` / `TALOSCONFIG` are exported by the
  workspace `.envrc` from `WORKSPACE_ROOT`.
- Known clusters: `docker-dev` (Docker Desktop, dual host/container contexts),
  `optiplex-admin`, `central01` (Cisco UCS).
- `docker-dev` uses two kubectl contexts: `admin@docker-dev-host` (from the host)
  and `admin@docker-dev-container` (from inside a container/devcontainer). The
  `.envrc` selects the right one by detecting `/.dockerenv` / `$container`.

## Workflow

1. Confirm context before any mutating action:
   `kubectl config current-context`. On docker-dev verify host vs container.
2. Talos node ops go through `talosctl --talosconfig <path> --nodes <ip>`.
   Never apply machine config to a node without confirming the node IP and
   cluster.
3. KubeVirt VMs: `virtctl` for console/port-forward/start/stop. The SSH
   matchBlocks (`konductor`, `konductor-optiplex`, `runner-docker`) proxy through
   `virtctl port-forward ... vmi/<name> 22`.

## Common failures

- **Wrong context** — docker-dev host context can't reach in-cluster VIPs; the
  container context can't reach host ports. Match context to where you're running.
- **UID conflicts on VMI deploy** — a build user leaked into the sealed image.
  The fix is in the image build (cloud-init must NOT create the build host user;
  see git history), not in the running cluster. Do not chown around it live.
- **Stale host keys** — ephemeral VMs (`vmi.*`, `localhost:2222`) rotate keys;
  their SSH matchBlocks already set `StrictHostKeyChecking=no` + `/dev/null`
  known_hosts. Don't add their keys to your real known_hosts.

## Conventions

- Talos is declarative — change machine config, `talosctl apply`, never SSH in
  and mutate a node by hand.
- Cluster credentials are generated artifacts; never commit `kubeconfig` /
  `talosconfig` or read them to extract secrets.
