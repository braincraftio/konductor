#!/usr/bin/env bash
# =============================================================================
# Konductor Instance k901 Deployment Script
# =============================================================================
# Wrapper around advanced/deploy.sh with instance-specific naming.
#
# Usage:
#   ./deploy.sh              # Deploy instance
#   ./deploy.sh --teardown   # Remove instance
#   ./deploy.sh --get-ssh-key # Get SSH private key
# =============================================================================

set -euo pipefail

INSTANCE="k901"
NAMESPACE="konductor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/../../advanced"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Teardown
# =============================================================================
teardown() {
    log_info "Tearing down instance $INSTANCE..."

    # Delete Job first
    kubectl delete job "${INSTANCE}-kubeconfig-generator" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=30s || true

    # Delete VM
    kubectl delete vm "$INSTANCE" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s || true

    # Delete VMI if orphaned
    kubectl delete vmi "$INSTANCE" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=30s || true

    # Delete DataVolume
    kubectl delete dv "${INSTANCE}-root" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s || true

    # Delete secrets
    for secret in "${INSTANCE}-userdata" "${INSTANCE}-networkdata" "${INSTANCE}-ssh-key" "${INSTANCE}-kubeconfig"; do
        kubectl delete secret "$secret" -n "$NAMESPACE" --ignore-not-found || true
    done

    # NOTE: PVCs NOT deleted to preserve data
    # To delete: kubectl delete pvc -n konductor ${INSTANCE}-git ${INSTANCE}-usrbinkat-home

    log_info "Teardown complete for $INSTANCE"
}

# =============================================================================
# Get SSH Key
# =============================================================================
get_ssh_key() {
    local key_file="$SCRIPT_DIR/${INSTANCE}.key"

    if ! kubectl get secret "${INSTANCE}-ssh-key" -n "$NAMESPACE" &>/dev/null; then
        log_error "SSH key secret not found. Run deploy first."
        exit 1
    fi

    kubectl get secret "${INSTANCE}-ssh-key" -n "$NAMESPACE" \
        -o jsonpath='{.data.private_key}' | base64 -d > "$key_file"
    chmod 600 "$key_file"

    log_info "Private key saved to: $key_file"
    log_info "SSH: ssh -i $key_file usrbinkat@<IP>"
}

# =============================================================================
# Ensure SSH Key
# =============================================================================
ensure_ssh_key() {
    if kubectl get secret "${INSTANCE}-ssh-key" -n "$NAMESPACE" &>/dev/null; then
        log_info "SSH key secret already exists for $INSTANCE"
        return
    fi

    local pub_key="" priv_key=""

    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        pub_key="$HOME/.ssh/id_ed25519.pub"
        priv_key="$HOME/.ssh/id_ed25519"
    elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        pub_key="$HOME/.ssh/id_rsa.pub"
        priv_key="$HOME/.ssh/id_rsa"
    fi

    if [[ -n "$pub_key" ]]; then
        log_info "Using existing SSH key for $INSTANCE"
        kubectl create secret generic "${INSTANCE}-ssh-key" \
            -n "$NAMESPACE" \
            --from-file=key="$pub_key" \
            --from-file=private_key="$priv_key"
    else
        log_info "Generating new SSH key for $INSTANCE..."
        local tmpdir=$(mktemp -d)
        ssh-keygen -t ed25519 -f "$tmpdir/$INSTANCE" -N "" -C "${INSTANCE}@cluster" >/dev/null
        kubectl create secret generic "${INSTANCE}-ssh-key" \
            -n "$NAMESPACE" \
            --from-file=key="$tmpdir/${INSTANCE}.pub" \
            --from-file=private_key="$tmpdir/$INSTANCE"
        rm -rf "$tmpdir"
    fi

    log_info "SSH key stored in secret ${INSTANCE}-ssh-key"
}

# =============================================================================
# Wait for Job
# =============================================================================
wait_for_job() {
    local job_name="$1"
    local timeout=300

    log_info "Waiting for Job $job_name..."

    if kubectl wait --for=condition=complete --timeout="${timeout}s" "job/$job_name" -n "$NAMESPACE" &>/dev/null; then
        log_info "Job $job_name completed"
        return 0
    elif kubectl wait --for=condition=failed --timeout=5s "job/$job_name" -n "$NAMESPACE" &>/dev/null; then
        log_error "Job $job_name failed"
        kubectl logs -n "$NAMESPACE" "job/$job_name" --tail=20 || true
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
    case "${1:-}" in
        --teardown) teardown; exit 0 ;;
        --get-ssh-key) get_ssh_key; exit 0 ;;
        --help|-h)
            echo "Usage: $0 [--teardown|--get-ssh-key|--help]"
            exit 0
            ;;
    esac

    log_info "Deploying Konductor instance: $INSTANCE"

    # Ensure namespace exists
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Create SSH key
    ensure_ssh_key

    # Apply kustomize
    log_info "Applying kustomize configuration..."
    kubectl apply -k "$SCRIPT_DIR"

    # Wait for kubeconfig generator
    if kubectl get job "${INSTANCE}-kubeconfig-generator" -n "$NAMESPACE" &>/dev/null; then
        wait_for_job "${INSTANCE}-kubeconfig-generator" || true
    fi

    # Wait for VM
    log_info "Waiting for VM to be ready..."
    kubectl wait --for=condition=Ready --timeout=300s "vm/$INSTANCE" -n "$NAMESPACE" &>/dev/null || \
        log_warn "VM not ready yet"

    log_info ""
    log_info "Instance $INSTANCE deployed!"
    log_info "  Get SSH key: $0 --get-ssh-key"
    log_info "  Find IP: kubectl get vmi $INSTANCE -n $NAMESPACE"
    log_info "  Teardown: $0 --teardown"
}

main "$@"
