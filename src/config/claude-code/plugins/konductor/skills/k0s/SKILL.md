---
name: k0s
description: Konductor k0s Kubernetes workflows. Use when working with k0s or k0sctl commands, enabling services.k0s in the qcow2 VM, bumping k0s/k0sctl versions, debugging k0scontroller/k0sworker systemd units, creating/joining nodes with tokens, or generating kubeconfigs. Covers the k0s-nix flake input, versions.nix pins, NixOS-specific k0s constraints, and the full CLI surface of both tools.
---

# Konductor k0s

Konductor ships k0s (single-binary Kubernetes) and k0sctl as on-demand
capability. Nothing starts a cluster by default — many konductor consumers do
not use Kubernetes. Command reference below is captured from the shipped
binaries: k0s v1.35.5+k0s.0, k0sctl v0.31.1.

## Delivery facts

- **k0s binary** comes from the `k0s-nix` flake input's overlay
  (`pkgs.k0s_1_27`..`pkgs.k0s_1_35`; `pkgs.k0s` = latest). Konductor selects
  via `src/lib/versions.nix` `kubernetes.k0s.attr`. Ships in the konductor
  self-hosting tier (`src/packages/konductor.nix`) → `#konductor` devshell and
  the qcow2 VM PATH. Linux-only.
- **k0sctl** is pinned tip-of-spear in `src/overlays/k0s.nix` (nixpkgs
  channels lag upstream patch releases; built with `unstable.buildGoModule`
  because k0sctl ≥0.31.1 requires Go ≥1.26). Cross-platform; ships in the
  kubernetes client tier of `src/packages/cli.nix` next to kubectl/talosctl.
- **`services.k0s` NixOS module** is imported into the qcow2
  `konductorModule` and re-exported as `nixosModules.k0s`, **disabled by
  default** (`mkEnableOption`). Kube kernel prereqs (overlay/br_netfilter/
  nf_conntrack modules, bridge-nf-call + ip_forward sysctls) and networkd
  unmanaged patterns for CNI interfaces are pre-asserted in the image, inert
  until a node runs.

## NixOS constraints (load-bearing)

- **Never run `k0s install` / `k0s start` / `k0s stop`** on NixOS — `install`
  writes `/etc/systemd/system/<unit>.service` and fails on the read-only /etc
  (k0sproject/k0s#1318); `start`/`stop` drive that installed service. The
  systemd unit is declarative: `services.k0s.*`. Use `systemctl
  {start,stop,status} k0scontroller` (or `k0sworker`) against the declarative
  unit instead.
- **k0sctl cannot manage NixOS nodes** (its apply phase runs `k0s install`).
  Use k0sctl for non-NixOS targets; use `services.k0s` for NixOS/qcow2 nodes.
  Do not attempt the k0sctl→NixOS fork path — evaluated and rejected upstream
  (johbo/k0s-nix docs) as unmaintainable.
- Worker/controller units need `mount`/`kmod` on unit PATH and
  `/run/wrappers/bin` for CNI — the k0s-nix module handles this; do not
  hand-roll units.

## k0s CLI reference (v1.35.5+k0s.0)

Foreground node processes (what the systemd unit runs — also fine ad hoc
under sudo):

```bash
# Single-node cluster (controller + worker, no taints)
sudo k0s controller --single                     # implies --enable-worker
# Controller that also schedules work
sudo k0s controller --enable-worker --no-taints --token-file /etc/k0s/k0stoken
# Pure worker joining a controller
sudo k0s worker --token-file /etc/k0s/k0stoken   # or: k0s worker [join-token] / K0S_TOKEN env
```

Shared node flags (controller + worker): `-c/--config` (default
`/etc/k0s/k0s.yaml`, `-` = stdin), `--data-dir` (default `/var/lib/k0s` — DO
NOT change on an existing setup), `--kubelet-root-dir`,
`--kubelet-extra-args`, `--labels key=value,...`, `--taints key=value:effect`,
`--profile <worker-profile>`, `--cri-socket [remote|docker]:<path>`,
`--iptables-mode nft|legacy|auto`, `--ignore-pre-flight-checks`,
`--status-socket <path>`, `-l/--logging component=level,...`, `-d/--debug`.
Controller-only: `--single`, `--enable-worker`, `--no-taints`,
`--disable-components <list>` (applier-manager, autopilot, control-api,
coredns, csr-approver, endpoint-reconciler, helm, konnectivity-server,
kube-controller-manager, kube-proxy, kube-scheduler, metrics-server,
network-provider, node-role, system-rbac, update-prober, windows-node,
worker-config), `--enable-dynamic-config`, `--enable-metrics-scraper`,
`--init-only`, `--kube-controller-manager-extra-args`.

Inspection and access:

```bash
k0s status [-o json|yaml]                    # needs /run/k0s/status.sock (running node)
k0s status components                        # per-component health
k0s sysinfo [-o text|json|yaml]              # pre-flight checks (--controller/--worker toggles)
k0s version [-a|-j]                          # -a = all version info, -j = json
sudo k0s kubeconfig admin > ~/.kube/config   # admin kubeconfig to stdout
sudo k0s kubeconfig create <user> [--groups g1,g2] [--certificate-expires-after 8760h] \
  [--context-name my-cluster]                # signed user cert — CANNOT be revoked later
k0s kubectl get nodes                        # embedded kubectl (alias: k0s kc)
```

Config lifecycle:

```bash
k0s config create [--include-images] > k0s.yaml   # default config to stdout
k0s config validate --config k0s.yaml             # lint before shipping
k0s config status [-o yaml|json]                  # dynamic-config reconciliation (needs --enable-dynamic-config)
k0s config edit                                   # edits live dynamic config in $EDITOR
```

Join tokens (run on a controller with the node up):

```bash
k0s token create --role worker --expiry 100h      # role: worker|controller; expiry: 10m, 2h45m...
k0s token list [--role worker|controller]
k0s token invalidate <token-id>
k0s token pre-shared --role worker --cert <ca.crt> --url https://<controller>:9443/ \
  [--out <dir>] [--valid 24h]                     # offline token+secret file pair
```

etcd membership (HA controllers; run on the affected controller):

```bash
k0s etcd member-list                              # JSON member list
k0s etcd leave [--peer-address <ip>]              # remove self (or a peer) BEFORE decommissioning
```

Backup / restore / teardown (all require root):

```bash
sudo k0s backup --save-path /var/backups/         # '-' = stdout stream
sudo k0s restore /path/k0s_backup_*.tar.gz [--config-out restored-k0s.yaml]
sudo k0s reset                                    # uninstall node state; reboot after; NixOS: also disable services.k0s
```

Airgap and debug:

```bash
k0s airgap list-images [--all]                    # images for current (or every) config
k0s airgap list-images | k0s airgap bundle-artifacts -v -o image-bundle.tar
sudo k0s ctr -n k8s.io images ls                  # embedded containerd CLI (containerd 1.7.32);
                                                  # socket /var/lib/k0s/run/containerd.sock
```

## k0sctl CLI reference (v0.31.1) — non-NixOS targets only

Global flags on every command: `-d/--debug`, `--trace`, `--no-redact`.
Operation commands share: `-c/--config <path|glob|->` (default `k0sctl.yaml`,
repeatable), `--concurrency N` (default 30), `--dry-run` (EXPERIMENTAL),
`--force`, `--timeout <dur>` (0 = forever).

```bash
k0sctl init [--k0s] [-n cluster-name] [-C controller-count] [-u user] [-i key-path] \
  user@host1:22 user@host2 > k0sctl.yaml          # template; addresses also via stdin; --k0s embeds k0s config skeleton
k0sctl apply                                      # converge cluster to k0sctl.yaml
k0sctl apply --kubeconfig-out kubeconfig [--kubeconfig-api-address <addr>] \
  [--no-wait] [--no-drain] [--concurrent-uploads 5] [--evict-taint k=v:NoExecute] \
  [--restore-from k0s_backup.tar.gz]
k0sctl kubeconfig [--address <addr>] [-u admin] [-n k0s-cluster] > kubeconfig
k0sctl backup -o k0s_backup.tar.gz
k0sctl reset                                      # strip k0s from all hosts in config
k0sctl config status [-o wide]                    # dynamic config reconciliation events
k0sctl config edit                                # live dynamic config in $EDITOR
k0sctl version --k0s [--pre]                      # query latest upstream k0s release
k0sctl completion -s bash|zsh|fish
```

Known quirk: `k0sctl version` prints `version: (devel)` with the real version
on the `commit:` line (upstream versioninfo ldflag limitation) — parse
`commit:`, not `version:`.

## Declarative workflows (NixOS/qcow2)

1. **Declarative node**: enable in the qcow2 flake config and rebuild from
   `/opt/konductor/src`:
   `services.k0s = { enable = true; role = "single"; }` →
   `sudo nixos-rebuild switch --flake .#konductor`.
   Roles: `single`, `controller`, `controller+worker`, `worker`. Module
   options: `package`, `dataDir` (default `/var/lib/k0s`), `tokenFile`
   (default `/etc/k0s/k0stoken`), `clusterName`, `spec` (typed cluster
   config → generated `/etc/k0s/k0s.yaml`), `extraArgs` (must not contain
   `--data-dir/--config/--single/--token-file` — module-owned),
   `controller.isLeader`.
2. **Joining**: non-leader nodes gate on `tokenFile` existing
   (`ConditionPathExists`). Generate on the leader with `k0s token create`,
   place at `/etc/k0s/k0stoken`, `systemctl start k0sworker`. The file can be
   emptied after a successful join.
3. **Verify**: `systemctl status k0scontroller` (or `k0sworker`) →
   `k0s status` → `k0s kubectl get nodes`.

## Version bumps (tip-of-spear policy)

- **k0s**: `nix flake update k0s-nix`, then set `kubernetes.k0s.attr` in
  `src/lib/versions.nix` if a new minor series landed (e.g. `k0s_1_36`).
  Embedded Kubernetes tracks k0s upstream (k0s 1.35.x ↔ k8s 1.35.x) — not
  independently pinned. Check upstream: `k0sctl version --k0s`.
- **k0sctl**: bump `kubernetes.k0sctl.version` in `src/lib/versions.nix` and
  the `hash`/`vendorHash` pair in `src/overlays/k0s.nix`. Watch the Go
  toolchain floor in its go.mod — that is why the overlay builds with
  `unstable.buildGoModule`.

## Conventions

- Issues in k0s packaging/module behavior → contribute upstream to
  johbo/k0s-nix (MIT, explicitly upstreamable), not local forks.
- k0s coexists with docker in the VM; both runtimes' dynamic interfaces are
  networkd-unmanaged (`05-docker-unmanaged`, `06-kube-unmanaged` in
  `src/qcow2/default.nix`). New CNI interface patterns belong there.
- Cluster credentials (`admin.conf`, kubeconfigs, join tokens) are generated
  artifacts — never commit, never read to extract secrets. User certs from
  `k0s kubeconfig create` cannot be revoked; scope them with `--groups` and
  short `--certificate-expires-after` rather than handing out admin.
