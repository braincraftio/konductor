#!/usr/bin/env bash
# =============================================================================
# Forgejo Runner Instance k9fr01 Deployment Script
# =============================================================================
# Creates secrets and deploys a Forgejo runner instance.
#
# Usage:
#   ./deploy.sh              # Create secrets and deploy
#   ./deploy.sh --teardown   # Remove instance
#   ./deploy.sh --get-ssh-key # Get SSH private key
# =============================================================================

set -euo pipefail

INSTANCE="k9fr01"
NAMESPACE="forgejo-runners"
FORGEJO_NAMESPACE="forgejo"
FORGEJO_DEPLOYMENT="forgejo-deployment"
CERTMANAGER_NAMESPACE="cert-manager"
CA_SECRET_NAME="cluster-ca-root-secret"
RUNNER_LABELS="ubuntu-latest,nix,konductor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

    kubectl delete vm "$INSTANCE" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s || true
    kubectl delete vmi "$INSTANCE" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=30s || true
    kubectl delete dv "${INSTANCE}-root" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s || true
    kubectl delete job "${INSTANCE}-kubeconfig-generator" -n "$NAMESPACE" --ignore-not-found || true

    for secret in "${INSTANCE}-userdata" "${INSTANCE}-networkdata" "${INSTANCE}-ssh-key" "${INSTANCE}-kubeconfig" "${INSTANCE}-credentials"; do
        kubectl delete secret "$secret" -n "$NAMESPACE" --ignore-not-found || true
    done

    # NOTE: Workspace PVC NOT deleted to preserve data
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
    log_info "SSH: ssh -i $key_file runner@<IP>"
}

# =============================================================================
# Get or Generate Shared Secret
# =============================================================================
get_or_generate_secret() {
    local secret_file="/tmp/${INSTANCE}-secret-$$"

    if kubectl get secret "${INSTANCE}-credentials" -n "$NAMESPACE" &>/dev/null; then
        log_info "Using existing shared secret"
        kubectl get secret "${INSTANCE}-credentials" -n "$NAMESPACE" \
            -o jsonpath='{.data.secret}' | base64 -d > "$secret_file"
    else
        log_info "Generating new shared secret..."
        kubectl exec -n "$FORGEJO_NAMESPACE" "deployment/$FORGEJO_DEPLOYMENT" -- \
            forgejo forgejo-cli actions generate-secret --config /var/lib/gitea/custom/conf/app.ini 2>/dev/null > "$secret_file"

        kubectl create secret generic "${INSTANCE}-credentials" \
            -n "$NAMESPACE" \
            --from-file=secret="$secret_file" \
            --dry-run=client -o yaml | kubectl apply -f - >&2
    fi

    cat "$secret_file"
    rm -f "$secret_file"
}

# =============================================================================
# Register Runner
# =============================================================================
register_runner() {
    local secret="$1"

    log_info "Registering runner $INSTANCE on Forgejo..."

    kubectl exec -n "$FORGEJO_NAMESPACE" "deployment/$FORGEJO_DEPLOYMENT" -- \
        forgejo forgejo-cli actions register \
            --config /var/lib/gitea/custom/conf/app.ini \
            --secret "$secret" \
            --name "$INSTANCE" \
            --scope "" \
            --labels "$RUNNER_LABELS" \
        2>/dev/null || true

    log_info "Runner registered"
}

# =============================================================================
# Get Cluster CA
# =============================================================================
get_cluster_ca() {
    kubectl get secret "$CA_SECRET_NAME" -n "$CERTMANAGER_NAMESPACE" \
        -o jsonpath='{.data.ca\.crt}' | base64 -d
}

# =============================================================================
# Get Forgejo URL
# =============================================================================
get_forgejo_url() {
    local hostname

    hostname=$(kubectl get httproute -n envoy-gateway-system forgejo-https-httproute \
        -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)

    if [[ -z "$hostname" ]]; then
        hostname=$(kubectl get httproute -n "$FORGEJO_NAMESPACE" \
            -o jsonpath='{.items[0].spec.hostnames[0]}' 2>/dev/null || true)
    fi

    if [[ -z "$hostname" ]]; then
        hostname=$(kubectl get ingress -n "$FORGEJO_NAMESPACE" \
            -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || true)
    fi

    if [[ -z "$hostname" ]]; then
        log_error "Could not determine Forgejo URL"
        exit 1
    fi

    echo "https://$hostname"
}

# =============================================================================
# Ensure SSH Key
# =============================================================================
ensure_ssh_key() {
    if kubectl get secret "${INSTANCE}-ssh-key" -n "$NAMESPACE" &>/dev/null; then
        log_info "SSH key already exists for $INSTANCE"
        return
    fi

    log_info "Generating SSH key for $INSTANCE..."
    local tmpdir=$(mktemp -d)
    ssh-keygen -t ed25519 -f "$tmpdir/$INSTANCE" -N "" -C "${INSTANCE}@cluster" >/dev/null

    kubectl create secret generic "${INSTANCE}-ssh-key" \
        -n "$NAMESPACE" \
        --from-file=key="$tmpdir/${INSTANCE}.pub" \
        --from-file=private_key="$tmpdir/$INSTANCE"

    rm -rf "$tmpdir"
    log_info "SSH key stored in ${INSTANCE}-ssh-key"
}

# =============================================================================
# Create Userdata Secret
# =============================================================================
create_userdata_secret() {
    local cluster_ca="$1"
    local shared_secret="$2"
    local forgejo_url="$3"

    log_info "Creating userdata secret for $INSTANCE..."

    local userdata
    userdata=$(cat <<EOF
#cloud-config
# Forgejo Runner $INSTANCE Cloud-Init Configuration

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

fs_setup:
  - label: workspace
    filesystem: ext4
    device: /dev/disk/by-id/virtio-e4-runner-775-w
    partition: none
    overwrite: false

write_files:
  - path: /etc/konductor/cluster-ca.crt
    permissions: '0644'
    content: |
$(echo "$cluster_ca" | sed 's/^/      /')

  - path: /etc/containers/policy.json
    permissions: '0644'
    content: |
      {"default": [{"type": "insecureAcceptAnything"}]}

  - path: /etc/konductor/forgejo-runner/secret
    permissions: '0600'
    owner: runner:users
    content: |
      $shared_secret

  - path: /etc/konductor/forgejo-runner/url
    permissions: '0644'
    content: |
      $forgejo_url

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
  - [/run/current-system/sw/bin/systemctl, enable, --now, konductor-mount@e4-runner-775-w.service]
  - [/run/current-system/sw/bin/systemctl, enable, --now, konductor-mount@iso-root-755-m.kube.service]

  - [/run/current-system/sw/bin/ln, -sf, /workspace, /home/runner/workspace]
  - [/run/current-system/sw/bin/chown, -h, "runner:kc2", /home/runner/workspace]

  - [/run/current-system/sw/bin/mkdir, -p, /home/runner/.kube, /home/kc2admin/.kube]
  - [/run/current-system/sw/bin/cp, /mnt/kube/config, /home/runner/.kube/config]
  - [/run/current-system/sw/bin/cp, /mnt/kube/config, /home/kc2admin/.kube/config]
  - [/run/current-system/sw/bin/chown, -R, "runner:users", /home/runner/.kube]
  - [/run/current-system/sw/bin/chown, -R, "kc2admin:users", /home/kc2admin/.kube]
  - [/run/current-system/sw/bin/chmod, "600", /home/runner/.kube/config]
  - [/run/current-system/sw/bin/chmod, "600", /home/kc2admin/.kube/config]

  - /run/current-system/sw/bin/mkdir -p /home/runner/.config/forgejo-runner
  - /run/current-system/sw/bin/chown -R runner:users /home/runner/.config

  - |
    /run/wrappers/bin/sudo -u runner SSL_CERT_FILE=/etc/konductor/ca-bundle.crt \
      /run/current-system/sw/bin/forgejo-runner \
        --config /home/runner/.config/forgejo-runner/config.yaml \
        create-runner-file \
        --secret \$(/run/current-system/sw/bin/cat /etc/konductor/forgejo-runner/secret) \
        --instance \$(/run/current-system/sw/bin/cat /etc/konductor/forgejo-runner/url) \
        --name \$(/run/current-system/sw/bin/hostname) \
        --connect

  - [/run/current-system/sw/bin/systemctl, start, docker]
  - [/run/current-system/sw/bin/systemctl, start, libvirtd]
  - [/run/current-system/sw/bin/systemctl, restart, forgejo-runner]

  - /run/wrappers/bin/sudo -u runner /run/current-system/sw/bin/nix build "github:braincraftio/konductor#devShells.x86_64-linux.ci" --no-link --refresh || true

final_message: |
  Cloud-Init Complete
  Instance: $INSTANCE
  Access: ssh runner@<IP>
EOF
)

    kubectl create secret generic "${INSTANCE}-userdata" \
        -n "$NAMESPACE" \
        --from-literal=userdata="$userdata" \
        --dry-run=client -o yaml | kubectl apply -f - >&2
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

    log_info "Deploying Forgejo Runner instance: $INSTANCE"

    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Get configuration
    local shared_secret=$(get_or_generate_secret)
    log_info "Secret: ${shared_secret:0:8}..."

    local cluster_ca=$(get_cluster_ca)
    log_info "Cluster CA: $(echo "$cluster_ca" | wc -l) lines"

    local forgejo_url=$(get_forgejo_url)
    log_info "Forgejo URL: $forgejo_url"

    # Register runner
    register_runner "$shared_secret"

    # Create secrets
    ensure_ssh_key
    create_userdata_secret "$cluster_ca" "$shared_secret" "$forgejo_url"

    # Apply kustomize
    log_info "Applying kustomize..."
    kubectl apply -k "$SCRIPT_DIR"

    # Wait for VM
    log_info "Waiting for VM..."
    kubectl wait --for=condition=Ready --timeout=300s "vm/$INSTANCE" -n "$NAMESPACE" &>/dev/null || \
        log_warn "VM not ready yet"

    log_info ""
    log_info "Instance $INSTANCE deployed!"
    log_info "  SSH key: $0 --get-ssh-key"
    log_info "  Find IP: kubectl get vmi $INSTANCE -n $NAMESPACE"
    log_info "  Runner UI: $forgejo_url/-/admin/actions/runners"
}

main "$@"
