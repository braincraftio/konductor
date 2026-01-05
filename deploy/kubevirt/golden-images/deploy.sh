#!/usr/bin/env bash
# =============================================================================
# Deploy Golden Images
# =============================================================================
# Deploys the golden image DataVolume and VolumeSnapshot to kubevirt namespace.
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Registry credentials secret exists in kubevirt namespace
#
# Usage:
#   ./deploy.sh [--snapshot-only]
#
# Steps:
#   1. Apply RBAC for cross-namespace cloning
#   2. Apply DataVolume (imports from registry, ~10 min first time)
#   3. Wait for DataVolume to succeed
#   4. Apply VolumeSnapshot
#   5. Wait for VolumeSnapshot to be ready
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="konductor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Apply registry credentials
apply_registry_credentials() {
    log_info "Applying registry credentials..."
    kubectl apply -f "$SCRIPT_DIR/registry-credentials.yaml"
}

# Apply RBAC
apply_rbac() {
    log_info "Applying RBAC for cross-namespace cloning..."
    kubectl apply -f "$SCRIPT_DIR/rbac.yaml"
}

# Apply DataVolume
apply_datavolume() {
    log_info "Applying golden image DataVolume..."
    kubectl apply -f "$SCRIPT_DIR/konductor-golden-dv.yaml"
}

# Wait for DataVolume to succeed
wait_for_datavolume() {
    local dv_name="konductor-golden"
    log_info "Waiting for DataVolume '$dv_name' to complete import..."
    log_info "This may take 5-10 minutes for initial import from registry"

    while true; do
        phase=$(kubectl get dv "$dv_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        progress=$(kubectl get dv "$dv_name" -n "$NAMESPACE" -o jsonpath='{.status.progress}' 2>/dev/null || echo "0%")

        case "$phase" in
            "Succeeded")
                log_info "DataVolume '$dv_name' completed successfully"
                return 0
                ;;
            "Failed")
                log_error "DataVolume '$dv_name' failed"
                kubectl describe dv "$dv_name" -n "$NAMESPACE"
                exit 1
                ;;
            "ImportInProgress")
                echo -ne "\r[INFO] Import in progress: $progress    "
                ;;
            *)
                echo -ne "\r[INFO] Phase: $phase                    "
                ;;
        esac
        sleep 5
    done
}

# Apply VolumeSnapshot
apply_snapshot() {
    log_info "Applying VolumeSnapshot..."
    kubectl apply -f "$SCRIPT_DIR/konductor-golden-snapshot.yaml"
}

# Wait for VolumeSnapshot to be ready
wait_for_snapshot() {
    local snapshot_name="konductor-golden-snapshot"
    log_info "Waiting for VolumeSnapshot '$snapshot_name' to be ready..."

    while true; do
        ready=$(kubectl get volumesnapshot "$snapshot_name" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")

        if [ "$ready" = "true" ]; then
            log_info "VolumeSnapshot '$snapshot_name' is ready"
            return 0
        fi

        echo -ne "\r[INFO] Waiting for snapshot to be ready...    "
        sleep 2
    done
}

# Main
main() {
    local snapshot_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --snapshot-only)
                snapshot_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_info "Deploying golden images to namespace: $NAMESPACE"

    if [ "$snapshot_only" = true ]; then
        log_info "Snapshot-only mode: skipping DataVolume creation"
        apply_snapshot
        wait_for_snapshot
    else
        apply_rbac
        apply_registry_credentials
        apply_datavolume
        wait_for_datavolume
        echo ""  # Newline after progress
        apply_snapshot
        wait_for_snapshot
    fi

    echo ""
    log_info "Golden image deployment complete!"
    log_info "VMs can now clone from: kubevirt/konductor-golden-snapshot"
    echo ""
    kubectl get dv,volumesnapshot -n "$NAMESPACE"
}

main "$@"
