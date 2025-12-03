#!/usr/bin/env bash
# shellcheck shell=bash
#
# nix.sh - Nix operations library for BrainCraft.io
#
# Provides:
# - Nix installation and configuration
# - Flake operations
# - Shell management
# - Binary cache configuration
# - Bash 3.2 compatibility
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/nix.sh"
#
# Shellcheck directives:
# - SC1091: Sourced files are validated separately and paths are dynamic
# - SC2034: Variables are exported for use by sourcing scripts
# - SC2154: Variables (colors, symbols, error codes) are defined in sourced files
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# - SC2312: Command substitution in pipelines is intentional for data processing
# shellcheck disable=SC1091,SC2034,SC2154,SC2292,SC2312

# Guard against multiple sourcing
if [ -n "${_BCIO_NIX_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_NIX_SOURCED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/errors.sh"

# =============================================================================
# NIX DETECTION
# =============================================================================

# Check if Nix is installed
# Returns: 0 if installed, 1 otherwise
is_nix_installed() {
    command -v nix > /dev/null 2>&1
}

# Check if Nix daemon is running
# Returns: 0 if running, 1 otherwise
is_nix_daemon_running() {
    nix store ping > /dev/null 2>&1
}

# Check if flakes are enabled
# Returns: 0 if enabled, 1 otherwise
are_flakes_enabled() {
    nix flake --help > /dev/null 2>&1
}

# Get Nix version
# Output: Nix version string
get_nix_version() {
    if is_nix_installed; then
        nix --version 2> /dev/null | head -1
    else
        printf 'not installed'
    fi
}

# Get Nix store path
# Output: Path to Nix store
get_nix_store_path() {
    printf '/nix/store'
}

# Get Nix store size
# Output: Human-readable store size
get_nix_store_size() {
    if [ -d "/nix/store" ]; then
        du -sh /nix/store 2> /dev/null | cut -f1
    else
        printf 'N/A'
    fi
}

# =============================================================================
# NIX INSTALLATION
# =============================================================================

# Install Nix using Lix installer
# Arguments:
#   $1 - Platform (darwin, linux, wsl, container)
install_nix() {
    local platform="${1:-$(detect_platform)}"
    local installer_url="${NIX_INSTALLER_URL:-https://install.lix.systems/lix}"

    print_header "Installing Nix"

    if is_nix_installed; then
        print_status success "Nix is already installed: $(get_nix_version)"
        return 0
    fi

    print_status info "Platform: ${platform}"
    print_status info "Installer: ${installer_url}"

    # Download and run installer
    print_status info "Downloading Lix installer..."

    if command -v curl > /dev/null 2>&1; then
        curl -sSf "${installer_url}" | sh -s -- install
    elif command -v wget > /dev/null 2>&1; then
        wget -qO- "${installer_url}" | sh -s -- install
    else
        die "Neither curl nor wget found" "${ERR_TOOL_MISSING}"
    fi

    # Source Nix profile
    if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    fi

    # Verify installation
    if is_nix_installed; then
        print_status success "Nix installed successfully: $(get_nix_version)"
        return 0
    else
        die "Nix installation failed" "${ERR_NIX_NOT_INSTALLED}"
    fi
}

# Uninstall Nix
uninstall_nix() {
    print_header "Uninstalling Nix"

    if [ -f "/nix/nix-installer" ]; then
        print_status info "Using Determinate Systems uninstaller..."
        /nix/nix-installer uninstall --no-confirm
    elif [ -f "/nix/receipt.json" ]; then
        print_status warning "Uninstaller not found, manual cleanup required"
        printf '  sudo rm -rf /nix\n'
        printf '  Remove Nix entries from shell profiles\n'
        return 1
    else
        print_status warning "No Nix installation found"
        return 0
    fi
}

# =============================================================================
# NIX CONFIGURATION
# =============================================================================

# Configure Nix for flake development
configure_nix() {
    print_header "Configuring Nix"

    # Create user config directory
    local config_dir="${HOME}/.config/nix"
    mkdir -p "${config_dir}"

    # Write user configuration
    cat > "${config_dir}/nix.conf" << 'EOF'
# BrainCraft.io Nix Configuration
# Minimal user config - flake.nix provides substituters and keys via nixConfig

# Experimental Features (Flakes + nix-command)
experimental-features = nix-command flakes

# Trust flake-provided configuration (caches, keys, build settings)
accept-flake-config = true

# Optimization
auto-optimise-store = true
warn-dirty = false
allow-import-from-derivation = true
EOF

    print_status success "Created ~/.config/nix/nix.conf"

    # Add user to trusted-users if we have sudo access
    if command -v sudo > /dev/null 2>&1; then
        local current_user="${USER:-$(whoami)}"
        local nix_conf="/etc/nix/nix.conf"

        if [ -f "${nix_conf}" ]; then
            if ! grep -q "trusted-users.*${current_user}" "${nix_conf}" 2> /dev/null; then
                print_status info "Adding ${current_user} to trusted-users..."
                if ! grep -q "^trusted-users" "${nix_conf}"; then
                    echo "trusted-users = root ${current_user}" | sudo tee -a "${nix_conf}" > /dev/null
                else
                    sudo sed -i.bak "s/^trusted-users.*/& ${current_user}/" "${nix_conf}"
                fi
                print_status success "Added ${current_user} to trusted-users"

                # Restart daemon
                restart_nix_daemon
            else
                print_status info "User already in trusted-users"
            fi
        fi
    fi
}

# Restart Nix daemon
restart_nix_daemon() {
    print_status info "Restarting Nix daemon..."

    if command -v systemctl > /dev/null 2>&1; then
        if systemctl is-active --quiet nix-daemon 2> /dev/null; then
            sudo systemctl restart nix-daemon
            print_status success "Nix daemon restarted (systemd)"
            return 0
        fi
    fi

    if command -v launchctl > /dev/null 2>&1; then
        if sudo launchctl list 2> /dev/null | grep -q org.nixos.nix-daemon; then
            sudo launchctl kickstart -k system/org.nixos.nix-daemon
            print_status success "Nix daemon restarted (launchd)"
            return 0
        fi
    fi

    print_status warning "Could not restart Nix daemon automatically"
    return 1
}

# =============================================================================
# FLAKE OPERATIONS
# =============================================================================

# Get flake directory
# Output: Absolute path to flake directory
get_flake_dir() {
    local dir="${FLAKE_DIR:-${MISE_PROJECT_ROOT:-${PWD}}}"
    printf '%s' "${dir}"
}

# Check if in a flake directory
# Returns: 0 if in flake directory, 1 otherwise
is_flake_dir() {
    local dir
    dir="$(get_flake_dir)"
    [ -f "${dir}/flake.nix" ]
}

# Validate flake configuration
# Returns: 0 if valid, 1 otherwise
validate_flake() {
    local dir
    dir="$(get_flake_dir)"

    if [ ! -f "${dir}/flake.nix" ]; then
        print_status error "No flake.nix found in ${dir}"
        return 1
    fi

    print_status info "Validating flake configuration..."

    if nix flake check "${dir}" --no-build 2>&1; then
        print_status success "Flake configuration is valid"
        return 0
    else
        print_status error "Flake validation failed"
        return 1
    fi
}

# Update flake inputs
update_flake() {
    local dir
    dir="$(get_flake_dir)"

    if ! is_flake_dir; then
        die "Not in a flake directory" "${ERR_FLAKE_INVALID}"
    fi

    print_header "Updating Flake Inputs"

    cd "${dir}" || die "Cannot cd to ${dir}"

    print_status info "Fetching latest input versions..."
    nix flake update

    # Show what changed
    if command -v git > /dev/null 2>&1 && [ -d ".git" ]; then
        printf '\n%bChanges in flake.lock:%b\n' "${BOLD}" "${NC}"
        git diff flake.lock 2> /dev/null || true
    fi

    print_status success "Flake inputs updated"
}

# Build flake
# Arguments:
#   $1 - Optional output to build
build_flake() {
    local output="${1:-}"
    local dir
    dir="$(get_flake_dir)"

    if ! is_flake_dir; then
        die "Not in a flake directory" "${ERR_FLAKE_INVALID}"
    fi

    print_header "Building Flake"

    cd "${dir}" || die "Cannot cd to ${dir}"

    if [ -n "${output}" ]; then
        print_status info "Building .#${output}..."
        nix build ".#${output}"
    else
        print_status info "Building default output..."
        nix build
    fi

    print_status success "Build complete"
    ls -la result* 2> /dev/null || print_status info "No result links created"
}

# =============================================================================
# SHELL MANAGEMENT
# =============================================================================

# List available shells
# Output: Space-separated list of shell names
list_shells() {
    local dir
    dir="$(get_flake_dir)"

    if ! is_flake_dir; then
        printf 'default'
        return
    fi

    # Try to get shells from flake
    local shells
    shells=$(nix flake show "${dir}" --json 2> /dev/null \
                                                         | jq -r '.devShells | to_entries[].value | keys[]' 2> /dev/null \
                                                                      | sort -u | tr '\n' ' ')

    if [ -n "${shells}" ]; then
        printf '%s' "${shells}"
    else
        printf 'default'
    fi
}

# =============================================================================
# GARBAGE COLLECTION
# =============================================================================

# Run garbage collection
# Arguments:
#   $1 - Mode: standard, aggressive (default: standard)
run_gc() {
    local mode="${1:-standard}"

    print_header "Nix Garbage Collection"

    # Show current store size
    printf 'Current store size: %s\n\n' "$(get_nix_store_size)"

    case "${mode}" in
        aggressive)
            print_status info "Running aggressive garbage collection..."
            nix-collect-garbage -d
            nix-store --optimise
            ;;
        *)
            print_status info "Running standard garbage collection..."
            nix-collect-garbage
            ;;
    esac

    # Show new store size
    printf '\nNew store size: %s\n' "$(get_nix_store_size)"
    print_status success "Garbage collection complete"
}

# =============================================================================
# BINARY CACHE
# =============================================================================

# Enable Cachix cache
# Arguments:
#   $1 - Cache name
enable_cachix() {
    local cache_name="${1:-${CACHIX_NAME:-braincraftio}}"

    print_header "Enabling Binary Cache"

    if ! command -v cachix > /dev/null 2>&1; then
        print_status info "Installing cachix..."
        nix-env -iA cachix -f https://cachix.org/api/v1/install
    fi

    print_status info "Adding ${cache_name} cache..."
    cachix use "${cache_name}"

    print_status success "Binary cache enabled"
}

# Push to Cachix cache
# Arguments:
#   $1 - Cache name
push_to_cache() {
    local cache_name="${1:-${CACHIX_NAME:-braincraftio}}"
    local dir
    dir="$(get_flake_dir)"

    if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
        die "CACHIX_AUTH_TOKEN not set" "${ERR_CONFIG}"
    fi

    print_header "Pushing to Binary Cache"

    cd "${dir}" || die "Cannot cd to ${dir}"

    print_status info "Building and pushing to ${cache_name}..."
    nix build --json | jq -r '.[].outputs | to_entries[].value' | cachix push "${cache_name}"

    print_status success "Successfully pushed to cache"
}

# =============================================================================
# NIX INFORMATION
# =============================================================================

# Print Nix information
print_nix_info() {
    print_header "Nix Information"

    print_table_row "Version" "$(get_nix_version)"
    print_table_row "Store path" "$(get_nix_store_path)"
    print_table_row "Store size" "$(get_nix_store_size)"
    print_table_row "Daemon running" "$(is_nix_daemon_running && printf 'yes' || printf 'no')"
    print_table_row "Flakes enabled" "$(are_flakes_enabled && printf 'yes' || printf 'no')"
    print_table_row "Platform" "$(get_nix_system)"

    # Show flake info if in flake directory
    if is_flake_dir; then
        printf '\n'
        print_table_row "Flake directory" "$(get_flake_dir)"
        print_table_row "Available shells" "$(list_shells)"
    fi

    # Show channels
    printf '\n%bChannels:%b\n' "${BOLD}" "${NC}"
    nix-channel --list 2> /dev/null || printf '  (using flakes, no channels)\n'

    # Show registries
    printf '\n%bFlake Registries:%b\n' "${BOLD}" "${NC}"
    nix registry list 2> /dev/null | head -10 || printf '  (none configured)\n'
}
