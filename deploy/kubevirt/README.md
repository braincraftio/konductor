# Konductor KubeVirt Deployment

Deploy the Konductor NixOS development VM to any Kubernetes cluster with KubeVirt.

## Quick Start (Base)

The base configuration uses pod networking and ephemeral storage (containerDisk):

```bash
# 1. Deploy the VM
kubectl apply -k https://github.com/containercraft/konductor//deploy/kubevirt/base

# 2. Create SSH key secret from your public key
kubectl create secret generic konductor-ssh-key -n konductor \
  --from-file=key=$HOME/.ssh/id_ed25519.pub

# 3. Restart VM to pick up SSH key (if already running)
kubectl delete vmi konductor -n konductor
```

### Access the VM

```bash
# SSH via virtctl (pod networking - no direct IP access)
virtctl ssh kc2@vmi/konductor -n konductor
virtctl ssh kc2admin@vmi/konductor -n konductor

# With specific identity file
virtctl ssh -i ~/.ssh/id_ed25519 kc2@vmi/konductor -n konductor

# Run a command directly
virtctl ssh kc2@vmi/konductor -n konductor -c "ip a"

# Serial console
virtctl console konductor -n konductor

# VNC (graphical)
virtctl vnc konductor -n konductor
```

### Users

| User | Description | Sudo |
|------|-------------|------|
| `kc2` | Unprivileged user (uid 1000) | Power commands only |
| `kc2admin` | Admin user | Full NOPASSWD |

## Advanced Deployment

The advanced overlay adds:
- **Persistent storage** via DataVolumeTemplate (imported from registry)
- **macvtap networking** for direct L2 access to physical network
- **OVS bridge** for nested virtualization
- **16Gi RAM, 4 cores + hyperthreading**
- **host-passthrough CPU** for nested virt

### Prerequisites

1. **KubeVirt with CDI** installed
2. **Multus CNI** installed
3. **macvtap-cni device plugin** on nodes
4. **Open vSwitch + ovs-cni** on nodes
5. **StorageClass** `ceph-nvme-vm-block` (or edit `vm-patch.yaml`)

### Deploy Advanced

```bash
# 1. Deploy the VM with persistent storage and advanced networking
kubectl apply -k https://github.com/containercraft/konductor//deploy/kubevirt/overlays/advanced

# 2. Create SSH key secret
kubectl create secret generic konductor-ssh-key -n konductor \
  --from-file=key=$HOME/.ssh/id_ed25519.pub

# 3. Wait for DataVolume to import from registry
kubectl get dv -n konductor -w
```

### Access (Advanced)

With macvtap networking, the VM gets a real IP from your network via DHCP:

```bash
# Direct SSH (VM has real network IP)
ssh kc2@<VM_IP>
ssh kc2admin@<VM_IP>

# Or via virtctl
virtctl ssh kc2@vmi/konductor -n konductor
```

## SSH Key Injection

Both base and advanced use **QEMU Guest Agent** for SSH key injection. This means:

1. No need to edit YAML files with your SSH key
2. Keys are injected at runtime via the guest agent
3. You can update keys without rebuilding the VM

```bash
# Create secret from ed25519 key
kubectl create secret generic konductor-ssh-key -n konductor \
  --from-file=key=$HOME/.ssh/id_ed25519.pub

# Or from RSA key
kubectl create secret generic konductor-ssh-key -n konductor \
  --from-file=key=$HOME/.ssh/id_rsa.pub

# Update key (delete and recreate)
kubectl delete secret konductor-ssh-key -n konductor
kubectl create secret generic konductor-ssh-key -n konductor \
  --from-file=key=$HOME/.ssh/id_ed25519.pub
```

## Directory Structure

```
deploy/kubevirt/
├── README.md
├── base/
│   ├── kustomization.yaml          # Base kustomization
│   ├── namespace.yaml              # Namespace with PSA labels
│   └── konductor.yaml              # VM with containerDisk + pod networking
└── overlays/
    └── advanced/
        ├── kustomization.yaml              # Inherits from base
        ├── network-attachment-definitions.yaml  # macvtap + OVS NADs
        ├── networkdata.yaml                # Cloud-init network config
        ├── userdata.yaml                   # User config with bridge setup
        └── virtualmachine.yaml             # DataVolumeTemplate + macvtap
```

## Customization

### Change Resources (Base)

```yaml
# my-overlay/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/containercraft/konductor//deploy/kubevirt/base
patches:
  - target:
      kind: VirtualMachine
      name: konductor
    patch: |
      - op: replace
        path: /spec/template/spec/domain/cpu/cores
        value: 4
      - op: replace
        path: /spec/template/spec/domain/resources/requests/memory
        value: 8Gi
```

### Change Storage Class (Advanced)

Edit `overlays/advanced/virtualmachine.yaml`:
```yaml
spec:
  dataVolumeTemplates:
    - spec:
        pvc:
          storageClassName: your-storage-class  # Change this
```

### Change Physical NIC for macvtap (Advanced)

Edit `overlays/advanced/network-attachment-definitions.yaml`:
```yaml
metadata:
  annotations:
    # Change 'enp3s0' to your node's physical NIC
    k8s.v1.cni.cncf.io/resourceName: macvtap.network.kubevirt.io/enp3s0
```

## Image Details

The containerDisk contains a NixOS-based development workstation with:

- **Neovim** with full IDE configuration
- **Docker** and **libvirt** for container/VM workloads
- **Nix** package manager with flakes enabled
- **QEMU Guest Agent** for SSH key injection
- **Development tools**: git, tmux, starship, etc.

Base image: `docker.io/containercraft/konductor:qcow2`

## Notes

- **Base**: Disk is ephemeral - resets on VM restart (containerDisk pattern)
- **Advanced**: Disk is persistent - survives VM restarts (DataVolume from registry)
- First boot runs `nix build` to cache the devshell (takes a few minutes)
- SSH key injection requires QEMU Guest Agent (included in image)
