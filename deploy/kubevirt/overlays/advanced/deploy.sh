#!/usr/bin/env bash
# =============================================================================
# Konductor Advanced Deployment Script
# =============================================================================
# Automated deployment of the Konductor development VM (advanced variant).
#
# This script:
#   1. Creates namespace
#   2. Generates SSH key (idempotent)
#   3. Generates kubeconfig from ServiceAccount
#   4. Deploys the VirtualMachine with persistent storage
#
# Usage:
#   ./deploy.sh                    # Deploy with defaults
#   ./deploy.sh --teardown         # Remove all resources
#   ./deploy.sh --get-ssh-key      # Retrieve SSH private key
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - KubeVirt with CDI installed
#   - StorageClasses: ceph-nvme-vm-block, cephfs-nvme-vm
#   - macvtap and Linux bridge CNI configured
# =============================================================================

set -euo pipefail

# Configuration
NAMESPACE="konductor"
VM_NAME="konductor"
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
    log_info "Tearing down konductor advanced deployment..."

    # Delete Job first
    if kubectl get job konductor-kubeconfig-generator -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting kubeconfig-generator Job..."
        kubectl delete job konductor-kubeconfig-generator -n "$NAMESPACE" --wait=true --timeout=30s || true
    fi

    # Delete VM (graceful shutdown)
    if kubectl get vm "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting VirtualMachine..."
        kubectl delete vm "$VM_NAME" -n "$NAMESPACE" --wait=true --timeout=120s || true
    fi

    # Delete VMI if orphaned
    if kubectl get vmi "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting VirtualMachineInstance..."
        kubectl delete vmi "$VM_NAME" -n "$NAMESPACE" --wait=true --timeout=30s || true
    fi

    # Delete DataVolume
    if kubectl get dv "${VM_NAME}-root" -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting DataVolume..."
        kubectl delete dv "${VM_NAME}-root" -n "$NAMESPACE" --wait=true --timeout=120s || true
    fi

    # NOTE: PVCs are NOT deleted by default to preserve persistent data
    # To delete PVCs, run: kubectl delete pvc -n konductor konductor-git konductor-usrbinkat-home

    # Delete secrets
    for secret in konductor-userdata konductor-networkdata konductor-ssh-key konductor-kubeconfig; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
            log_info "Deleting secret $secret..."
            kubectl delete secret "$secret" -n "$NAMESPACE" || true
        fi
    done

    # Delete ServiceAccount and RBAC
    if kubectl get sa konductor-vm -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting ServiceAccount..."
        kubectl delete sa konductor-vm -n "$NAMESPACE" || true
    fi

    if kubectl get secret konductor-vm-token -n "$NAMESPACE" &>/dev/null; then
        log_info "Deleting ServiceAccount token secret..."
        kubectl delete secret konductor-vm-token -n "$NAMESPACE" || true
    fi

    if kubectl get clusterrolebinding konductor-vm-admin &>/dev/null; then
        log_info "Deleting ClusterRoleBinding..."
        kubectl delete clusterrolebinding konductor-vm-admin || true
    fi

    # Delete NADs
    for nad in macvtap br0; do
        if kubectl get net-attach-def "$nad" -n "$NAMESPACE" &>/dev/null; then
            log_info "Deleting NetworkAttachmentDefinition $nad..."
            kubectl delete net-attach-def "$nad" -n "$NAMESPACE" || true
        fi
    done

    log_info "Teardown complete"
}

# =============================================================================
# Create or Get SSH Key
# =============================================================================
# Stores BOTH public and private key in the secret for recoverability.
# Public key is used by QEMU Guest Agent for injection.
# Private key can be retrieved with: ./deploy.sh --get-ssh-key
#
# Preference order:
#   1. Existing secret (if found)
#   2. User's existing SSH key (~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)
#   3. Generate new key pair
ensure_ssh_key() {
    if kubectl get secret konductor-ssh-key -n "$NAMESPACE" &>/dev/null; then
        log_info "SSH key secret already exists"
        log_info "Retrieve private key: $0 --get-ssh-key"
        return
    fi

    local pub_key=""
    local priv_key=""

    # Check for user's existing SSH keys
    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        log_info "Found existing SSH key: $HOME/.ssh/id_ed25519.pub"
        pub_key="$HOME/.ssh/id_ed25519.pub"
        priv_key="$HOME/.ssh/id_ed25519"
    elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        log_info "Found existing SSH key: $HOME/.ssh/id_rsa.pub"
        pub_key="$HOME/.ssh/id_rsa.pub"
        priv_key="$HOME/.ssh/id_rsa"
    fi

    if [[ -n "$pub_key" ]]; then
        # Use existing key
        log_info "Using existing SSH key for VM access"
        kubectl create secret generic konductor-ssh-key \
            -n "$NAMESPACE" \
            --from-file=key="$pub_key" \
            --from-file=private_key="$priv_key"
        log_info "SSH key stored in secret konductor-ssh-key"
    else
        # Generate new key pair
        log_info "No existing SSH key found, generating new key pair..."
        local tmpdir
        tmpdir=$(mktemp -d)
        ssh-keygen -t ed25519 -f "$tmpdir/konductor" -N "" -C "konductor@cluster" >/dev/null

        # Store both public and private key in secret
        # 'key' = public key (used by QEMU Guest Agent)
        # 'private_key' = private key (for SSH access)
        kubectl create secret generic konductor-ssh-key \
            -n "$NAMESPACE" \
            --from-file=key="$tmpdir/konductor.pub" \
            --from-file=private_key="$tmpdir/konductor"

        rm -rf "$tmpdir"
        log_info "SSH key pair stored in secret konductor-ssh-key"
        log_info "Retrieve private key: $0 --get-ssh-key"
    fi
}

# =============================================================================
# Get SSH Private Key from Secret
# =============================================================================
get_ssh_key() {
    if ! kubectl get secret konductor-ssh-key -n "$NAMESPACE" &>/dev/null; then
        log_error "SSH key secret not found. Run deploy first."
        exit 1
    fi

    local key_file="$SCRIPT_DIR/konductor.key"
    kubectl get secret konductor-ssh-key -n "$NAMESPACE" \
        -o jsonpath='{.data.private_key}' | base64 -d > "$key_file"
    chmod 600 "$key_file"

    log_info "Private key saved to: $key_file"
    log_info "SSH commands:"
    log_info "  ssh -i $key_file usrbinkat@<IP>"
    log_info "  ssh -i $key_file kc2@<IP>"
    log_info "  ssh -i $key_file kc2admin@<IP>"
}

# =============================================================================
# Wait for Job Completion
# =============================================================================
wait_for_job() {
    local job_name="$1"
    local timeout=300  # 5 minutes

    log_info "Waiting for Job $job_name to complete (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=complete \
        --timeout="${timeout}s" \
        "job/$job_name" -n "$NAMESPACE" &>/dev/null; then
        log_info "Job $job_name completed successfully"
        return 0
    elif kubectl wait --for=condition=failed \
        --timeout=5s \
        "job/$job_name" -n "$NAMESPACE" &>/dev/null; then
        log_error "Job $job_name failed"
        log_error "Job logs:"
        kubectl logs -n "$NAMESPACE" "job/$job_name" --tail=50 || true
        return 1
    else
        log_error "Job $job_name timed out"
        return 1
    fi
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
            echo "  (no args)      Deploy konductor advanced VM"
            echo "  --teardown     Remove all resources"
            echo "  --get-ssh-key  Retrieve SSH private key from secret"
            echo ""
            exit 0
            ;;
    esac

    log_info "Deploying Konductor Advanced VM..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
    fi

    # Ensure SSH key exists
    ensure_ssh_key

    # Apply kustomize configuration (creates ServiceAccount, NADs, secrets, VM)
    log_info "Applying kustomize configuration..."
    kubectl apply -k "$SCRIPT_DIR"

    # Wait for kubeconfig generator Job to complete
    if kubectl get job konductor-kubeconfig-generator -n "$NAMESPACE" &>/dev/null; then
        if ! wait_for_job konductor-kubeconfig-generator; then
            log_error "Failed to generate kubeconfig"
            exit 1
        fi

        # Show Job logs
        log_info "Kubeconfig generator Job logs:"
        kubectl logs -n "$NAMESPACE" job/konductor-kubeconfig-generator --tail=20 || true
    fi

    # Check if kubeconfig secret was created
    if kubectl get secret konductor-kubeconfig -n "$NAMESPACE" &>/dev/null; then
        log_info "✓ Kubeconfig secret created successfully"
    else
        log_warn "Kubeconfig secret not found (may be optional)"
    fi

    # Wait for VM to be ready
    log_info "Waiting for VM to be ready..."
    if kubectl wait --for=condition=Ready \
        --timeout=300s \
        "vm/$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_info "✓ VM is ready"
    else
        log_warn "VM not ready yet (may still be starting)"
    fi

    # Get VM status
    log_info ""
    log_info "VM Status:"
    kubectl get vm,vmi,dv,pvc -n "$NAMESPACE" -l app=konductor || true

    log_info ""
    log_info "Deployment complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Get SSH key: $0 --get-ssh-key"
    log_info "  2. Find VM IP: kubectl get vmi -n $NAMESPACE"
    log_info "  3. SSH to VM: ssh -i konductor.key usrbinkat@<IP>"
    log_info ""
    log_info "To remove everything: $0 --teardown"
}

main "$@"
