#!/usr/bin/env bash
# =============================================================================
# Forgejo Runner Deployment Script
# =============================================================================
# Fully automated deployment of Forgejo CI/CD runner VMs.
#
# This script:
#   1. Creates namespace
#   2. Generates shared secret (idempotent)
#   3. Registers runner on Forgejo server
#   4. Extracts cluster CA from cert-manager
#   5. Creates all required secrets
#   6. Deploys the VirtualMachine
#
# Usage:
#   ./deploy.sh                    # Deploy with defaults
#   ./deploy.sh --teardown         # Remove all resources
#   ./deploy.sh --dry-run          # Show what would be created
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Forgejo server running in forgejo namespace
#   - cert-manager with cluster-ca-root-secret
#   - SSH key pair (generated if missing)
# =============================================================================

set -euo pipefail

# Configuration
NAMESPACE="forgejo-runners"
FORGEJO_NAMESPACE="forgejo"
FORGEJO_DEPLOYMENT="forgejo-deployment"
CERTMANAGER_NAMESPACE="cert-manager"
CA_SECRET_NAME="cluster-ca-root-secret"
RUNNER_NAME="forgejo-runner"
RUNNER_LABELS="ubuntu-latest,nix,konductor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Teardown
# =============================================================================
teardown() {
    log_info "Tearing down forgejo-runners deployment..."

    # Delete VM first (graceful shutdown)
    if kubectl get vm "$RUNNER_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting VirtualMachine..."
        kubectl delete vm "$RUNNER_NAME" -n "$NAMESPACE" --wait=true --timeout=60s || true
    fi

    # Delete VMI if orphaned
    if kubectl get vmi "$RUNNER_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting VirtualMachineInstance..."
        kubectl delete vmi "$RUNNER_NAME" -n "$NAMESPACE" --wait=true --timeout=30s || true
    fi

    # Delete DataVolume
    if kubectl get dv "${RUNNER_NAME}-root" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting DataVolume..."
        kubectl delete dv "${RUNNER_NAME}-root" -n "$NAMESPACE" --wait=true --timeout=120s || true
    fi

    # NOTE: Workspace PVC is NOT deleted by default to preserve persistent data
    # To delete workspace PVC, run: kubectl delete pvc -n forgejo-runners forgejo-runner-workspace

    # Delete secrets (including credentials to allow re-registration with new URL)
    for secret in forgejo-runner-userdata forgejo-runner-networkdata forgejo-runner-ssh-key forgejo-runner-credentials; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
            log_info "Deleting secret $secret..."
            kubectl delete secret "$secret" -n "$NAMESPACE" || true
        fi
    done

    # Delete NAD
    if kubectl get net-attach-def ovs-br0 -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting NetworkAttachmentDefinition..."
        kubectl delete net-attach-def ovs-br0 -n "$NAMESPACE" || true
    fi

    # Optionally delete namespace (commented out to preserve for re-deployment)
    # kubectl delete namespace "$NAMESPACE" --wait=true || true

    log_info "Teardown complete"
}

# =============================================================================
# Get or Generate Shared Secret
# =============================================================================
get_or_generate_secret() {
    local secret_file="/tmp/forgejo-runner-secret-$$"

    # Check if we have a stored secret in the cluster
    if kubectl get secret forgejo-runner-credentials -n "$NAMESPACE" &>/dev/null; then
        log_info "Using existing shared secret from cluster"
        kubectl get secret forgejo-runner-credentials -n "$NAMESPACE" \
            -o jsonpath='{.data.secret}' | base64 -d > "$secret_file"
    else
        log_info "Generating new shared secret..."
        kubectl exec -n "$FORGEJO_NAMESPACE" "deployment/$FORGEJO_DEPLOYMENT" -- \
            forgejo forgejo-cli actions generate-secret --config /var/lib/gitea/custom/conf/app.ini 2>/dev/null > "$secret_file"

        # Store the secret for future use (redirect apply output to stderr)
        kubectl create secret generic forgejo-runner-credentials \
            -n "$NAMESPACE" \
            --from-file=secret="$secret_file" \
            --dry-run=client -o yaml | kubectl apply -f - >&2
    fi

    cat "$secret_file"
    rm -f "$secret_file"
}

# =============================================================================
# Register Runner on Forgejo Server
# =============================================================================
register_runner() {
    local secret="$1"

    log_info "Registering runner on Forgejo server (idempotent)..."

    kubectl exec -n "$FORGEJO_NAMESPACE" "deployment/$FORGEJO_DEPLOYMENT" -- \
        forgejo forgejo-cli actions register \
            --config /var/lib/gitea/custom/conf/app.ini \
            --secret "$secret" \
            --name "$RUNNER_NAME" \
            --scope "" \
            --labels "$RUNNER_LABELS" \
        2>/dev/null || true  # Ignore errors (already registered is fine)

    log_info "Runner registered"
}

# =============================================================================
# Extract Cluster CA
# =============================================================================
get_cluster_ca() {
    log_info "Extracting cluster CA from cert-manager..."

    kubectl get secret "$CA_SECRET_NAME" -n "$CERTMANAGER_NAMESPACE" \
        -o jsonpath='{.data.ca\.crt}' | base64 -d
}

# =============================================================================
# Get Forgejo Server URL
# =============================================================================
get_forgejo_url() {
    local hostname

    # Use public git.braincraft.io endpoint (HTTPRoute)
    hostname=$(kubectl get httproute -n envoy-gateway-system forgejo-https-httproute \
        -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)

    # Fall back to forgejo namespace HTTPRoute
    if [[ -z "$hostname" ]]; then
        hostname=$(kubectl get httproute -n "$FORGEJO_NAMESPACE" \
            -o jsonpath='{.items[0].spec.hostnames[0]}' 2>/dev/null || true)
    fi

    # Fall back to Ingress
    if [[ -z "$hostname" ]]; then
        hostname=$(kubectl get ingress -n "$FORGEJO_NAMESPACE" \
            -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || true)
    fi

    if [[ -z "$hostname" ]]; then
        log_error "Could not determine Forgejo server URL"
        exit 1
    fi

    echo "https://$hostname"
}

# =============================================================================
# Create or Get SSH Key
# =============================================================================
# Stores BOTH public and private key in the secret for recoverability.
# Public key is used by QEMU Guest Agent for injection.
# Private key can be retrieved with: ./deploy.sh --get-ssh-key
ensure_ssh_key() {
    if kubectl get secret forgejo-runner-ssh-key -n "$NAMESPACE" &>/dev/null; then
        log_info "SSH key secret already exists"
        log_info "Retrieve private key: $0 --get-ssh-key"
        return
    fi

    log_info "Generating SSH key pair..."
    local tmpdir
    tmpdir=$(mktemp -d)
    ssh-keygen -t ed25519 -f "$tmpdir/forgejo-runner" -N "" -C "forgejo-runner@cluster" >/dev/null

    # Store both public and private key in secret
    # 'key' = public key (used by QEMU Guest Agent)
    # 'private_key' = private key (for SSH access)
    kubectl create secret generic forgejo-runner-ssh-key \
        -n "$NAMESPACE" \
        --from-file=key="$tmpdir/forgejo-runner.pub" \
        --from-file=private_key="$tmpdir/forgejo-runner"

    rm -rf "$tmpdir"
    log_info "SSH key pair stored in secret forgejo-runner-ssh-key"
    log_info "Retrieve private key: $0 --get-ssh-key"
}

# =============================================================================
# Get SSH Private Key from Secret
# =============================================================================
get_ssh_key() {
    if ! kubectl get secret forgejo-runner-ssh-key -n "$NAMESPACE" &>/dev/null; then
        log_error "SSH key secret not found. Run deploy first."
        exit 1
    fi

    local key_file="$SCRIPT_DIR/forgejo-runner.key"
    kubectl get secret forgejo-runner-ssh-key -n "$NAMESPACE" \
        -o jsonpath='{.data.private_key}' | base64 -d > "$key_file"
    chmod 600 "$key_file"

    log_info "Private key saved to: $key_file"
    log_info "SSH command: ssh -i $key_file runner@<IP>"
}

# =============================================================================
# Create Userdata Secret
# =============================================================================
create_userdata_secret() {
    local cluster_ca="$1"
    local shared_secret="$2"
    local forgejo_url="$3"

    log_info "Creating userdata secret..."

    # Generate the complete cloud-init userdata
    local userdata
    userdata=$(cat <<EOF
#cloud-config
# Forgejo Runner Cloud-Init Configuration
# Generated by deploy.sh - DO NOT EDIT MANUALLY

# Force resize root partition and filesystem on every boot (PER_ALWAYS)
# Allows DataVolume storage size increases to take effect
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: true
resize_rootfs: true

users:
  - name: runner
    uid: 1003
    gecos: Forgejo CI/CD Runner
    groups: users, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
  - name: kc2admin
    uid: 1002
    gecos: Konductor Admin
    groups: users, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

# Format workspace disk on first boot if not already formatted
# Mounting is handled by konductor-mount@.service (systemd template)
#
# Serial ID format: <fstype>-<user>-<mode>-<path>
#   e4-root-775-workspace → /dev/disk/by-id/virtio-e4-root-775-workspace
fs_setup:
  - label: workspace
    filesystem: ext4
    device: /dev/disk/by-id/virtio-e4-root-775-workspace
    partition: none
    overwrite: false

write_files:
  # Cluster CA Certificate
  - path: /etc/konductor/cluster-ca.crt
    permissions: '0644'
    content: |
$(echo "$cluster_ca" | sed 's/^/      /')

  # Containers policy for skopeo/podman
  - path: /etc/containers/policy.json
    permissions: '0644'
    content: |
      {"default": [{"type": "insecureAcceptAnything"}]}

  # Forgejo Runner Shared Secret
  - path: /etc/konductor/forgejo-runner/secret
    permissions: '0600'
    owner: runner:users
    content: |
      $shared_secret

  # Forgejo Server URL
  - path: /etc/konductor/forgejo-runner/url
    permissions: '0644'
    content: |
      $forgejo_url

  # Forgejo Runner Configuration
  - path: /home/runner/.config/forgejo-runner/config.yaml
    permissions: '0600'
    owner: runner:users
    content: |
      runner:
        file: /home/runner/.config/forgejo-runner/.runner
        capacity: 2
        timeout: 3h
        insecure: false
        fetch_timeout: 5s
        fetch_interval: 2s
        labels:
          - "ubuntu-latest:host"
          - "nix:host"
          - "konductor:host"

runcmd:
  # -----------------------------------------------------------------------
  # Mount persistent volumes via systemd template service
  # -----------------------------------------------------------------------
  # konductor-mount@.service parses serial ID to mount:
  #   Serial ID format: <fstype>-<user>-<mode>-<path>
  #
  #   e4-root-775-workspace → mount -t ext4 /dev/... /workspace, chown root:users, chmod 775
  #   iso-root-755-m.kube   → mount -t iso9660 -o ro /dev/... /mnt/kubeconfig, chown root:root, chmod 755
  # -----------------------------------------------------------------------
  - [/run/current-system/sw/bin/systemctl, enable, --now, konductor-mount@e4-root-775-workspace.service]
  - [/run/current-system/sw/bin/systemctl, enable, --now, konductor-mount@iso-root-755-m.kube.service]

  # Create symlink: /home/runner/workspace → /workspace (mounted by systemd)
  - [/run/current-system/sw/bin/ln, -sf, /workspace, /home/runner/workspace]
  - [/run/current-system/sw/bin/chown, -h, "runner:users", /home/runner/workspace]

  # Copy kubeconfig to user directories (konductor-mount@iso-root-755-m.kube.service mounts it to /mnt/kubeconfig)
  - [/run/current-system/sw/bin/mkdir, -p, /home/runner/.kube, /home/kc2admin/.kube]
  - [/run/current-system/sw/bin/cp, /mnt/kubeconfig/config, /home/runner/.kube/config]
  - [/run/current-system/sw/bin/cp, /mnt/kubeconfig/config, /home/kc2admin/.kube/config]
  - [/run/current-system/sw/bin/chown, -R, "runner:users", /home/runner/.kube]
  - [/run/current-system/sw/bin/chown, -R, "kc2admin:users", /home/kc2admin/.kube]
  - [/run/current-system/sw/bin/chmod, "600", /home/runner/.kube/config]
  - [/run/current-system/sw/bin/chmod, "600", /home/kc2admin/.kube/config]

  # Ensure runner config directory exists
  # Note: NixOS requires full paths - binaries in /run/current-system/sw/bin
  - /run/current-system/sw/bin/mkdir -p /home/runner/.config/forgejo-runner
  - /run/current-system/sw/bin/chown -R runner:users /home/runner/.config

  # Create runner file from shared secret (idempotent registration)
  # --config flag is required so forgejo-runner knows where to save .runner file
  - |
    /run/wrappers/bin/sudo -u runner SSL_CERT_FILE=/etc/konductor/ca-bundle.crt \
      /run/current-system/sw/bin/forgejo-runner \
        --config /home/runner/.config/forgejo-runner/config.yaml \
        create-runner-file \
        --secret \$(/run/current-system/sw/bin/cat /etc/konductor/forgejo-runner/secret) \
        --instance \$(/run/current-system/sw/bin/cat /etc/konductor/forgejo-runner/url) \
        --name \$(/run/current-system/sw/bin/hostname) \
        --connect

  # Start services
  - [/run/current-system/sw/bin/systemctl, start, docker]
  - [/run/current-system/sw/bin/systemctl, start, libvirtd]
  - [/run/current-system/sw/bin/systemctl, restart, forgejo-runner]

  # Pre-cache konductor CI devshell for faster job startup
  - /run/wrappers/bin/sudo -u runner /run/current-system/sw/bin/nix build "github:braincraftio/konductor#devShells.x86_64-linux.ci" --no-link --refresh || true

final_message: |
  Cloud-Init Complete
  Forgejo Runner: \$(hostname)
  CA Trust: /etc/konductor/ca-bundle.crt
  Access: ssh runner@<IP> or ssh kc2admin@<IP>
EOF
)

    # Create the secret (redirect apply output to stderr)
    kubectl create secret generic forgejo-runner-userdata \
        -n "$NAMESPACE" \
        --from-literal=userdata="$userdata" \
        --dry-run=client -o yaml | kubectl apply -f - >&2
}

# =============================================================================
# Main
# =============================================================================
main() {
    # Parse arguments
    case "${1:-}" in
        --teardown)
            teardown
            exit 0
            ;;
        --get-ssh-key)
            get_ssh_key
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [--teardown|--get-ssh-key|--help]"
            echo ""
            echo "Commands:"
            echo "  (no args)      Create secrets for deployment"
            echo "  --teardown     Remove all resources"
            echo "  --get-ssh-key  Retrieve SSH private key from secret"
            echo ""
            echo "After creating secrets: kubectl apply -k $SCRIPT_DIR"
            exit 0
            ;;
    esac

    log_info "Creating Forgejo Runner secrets..."

    # Create namespace first (needed for secrets)
    kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

    # Get configuration
    log_info "Gathering configuration..."
    local shared_secret
    shared_secret=$(get_or_generate_secret)
    log_info "Shared secret: ${shared_secret:0:8}..."

    local cluster_ca
    cluster_ca=$(get_cluster_ca)
    log_info "Cluster CA extracted ($(echo "$cluster_ca" | wc -l) lines)"

    local forgejo_url
    forgejo_url=$(get_forgejo_url)
    log_info "Forgejo URL: $forgejo_url"

    # Register runner on server
    register_runner "$shared_secret"

    # Ensure SSH key exists
    ensure_ssh_key

    # Create userdata secret (networkdata is static, handled by kustomize)
    create_userdata_secret "$cluster_ca" "$shared_secret" "$forgejo_url"

    log_info ""
    log_info "Secrets created. Now apply kustomize:"
    log_info "  kubectl apply -k $SCRIPT_DIR"
    log_info ""
    log_info "After VM starts:"
    log_info "  SSH: ssh -i $SCRIPT_DIR/forgejo-runner.key runner@<IP>"
    log_info "  UI:  $forgejo_url/-/admin/actions/runners"
}

main "$@"
