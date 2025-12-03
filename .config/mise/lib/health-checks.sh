#!/usr/bin/env bash
# shellcheck shell=bash
#
# health-checks.sh - Health check framework for BrainCraft.io
#
# Provides:
# - Categorized health checks (critical, important, optional)
# - Parallel array storage for bash 3.2 compatibility
# - Nix-specific health checks
# - System resource checks
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/health-checks.sh"
#   run_health_check "Nix daemon" "check_nix_daemon" "critical"
#   print_health_summary
#
# Categories:
#   critical  - Must pass for system to function
#   important - Should pass for optimal operation
#   optional  - Nice to have, informational
#
# Shellcheck directives:
# - SC1091: Sourced files are validated separately and paths are dynamic
# - SC2034: Variables are exported for use by sourcing scripts
# - SC2154: Variables (colors, symbols) are defined in sourced common.sh
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# - SC2312: Command substitution in pipelines is intentional for data extraction
# shellcheck disable=SC1091,SC2034,SC2154,SC2292,SC2312

# Guard against multiple sourcing
if [ -n "${_BCIO_HEALTH_CHECKS_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_HEALTH_CHECKS_SOURCED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/errors.sh"

# =============================================================================
# HEALTH CHECK STORAGE (Parallel Arrays for bash 3.2)
# =============================================================================

# Storage arrays
HEALTH_CHECK_NAMES=()
HEALTH_CHECK_RESULTS=()
HEALTH_CHECK_OUTPUTS=()
HEALTH_CHECK_CATEGORIES=()
HEALTH_CHECK_DURATIONS=()

# Counters
HEALTH_CHECK_TOTAL=0
HEALTH_CHECK_PASSED=0
HEALTH_CHECK_FAILED=0
HEALTH_CHECK_SKIPPED=0

# =============================================================================
# CORE HEALTH CHECK FUNCTIONS
# =============================================================================

# Reset all health check data
reset_health_checks() {
    HEALTH_CHECK_NAMES=()
    HEALTH_CHECK_RESULTS=()
    HEALTH_CHECK_OUTPUTS=()
    HEALTH_CHECK_CATEGORIES=()
    HEALTH_CHECK_DURATIONS=()
    HEALTH_CHECK_TOTAL=0
    HEALTH_CHECK_PASSED=0
    HEALTH_CHECK_FAILED=0
    HEALTH_CHECK_SKIPPED=0
}

# Run a health check and store results
# Arguments:
#   $1 - Check name (display name)
#   $2 - Check command (function name or shell command)
#   $3 - Category: critical, important, optional (default: important)
# Returns: 0 on pass, 1 on fail
run_health_check() {
    local check_name="${1:-Unknown check}"
    local check_command="${2:-true}"
    local category="${3:-important}"

    local output=""
    local exit_code=0
    local start_time end_time duration

    # GNU date provided by flake (works on all platforms)
    start_time=$(date +%s.%N)

    # Extract first word to check if it is a function
    local first_word="${check_command%% *}"

    # Execute the check
    if declare -F "${first_word}" > /dev/null 2>&1; then
        # It is a function - evaluate in current shell
        output=$(eval "${check_command}" 2>&1)
        exit_code=$?
    else
        # It is a shell command - execute safely
        output=$(bash -c "${check_command}" 2>&1)
        exit_code=$?
    fi

    # Calculate duration using GNU date and bc from flake
    end_time=$(date +%s.%N)
    duration=$(printf '%s\n' "${end_time} - ${start_time}" | bc)

    # Store results
    HEALTH_CHECK_NAMES+=("${check_name}")
    HEALTH_CHECK_RESULTS+=("${exit_code}")
    HEALTH_CHECK_OUTPUTS+=("${output}")
    HEALTH_CHECK_CATEGORIES+=("${category}")
    HEALTH_CHECK_DURATIONS+=("${duration}")

    # Update counters
    HEALTH_CHECK_TOTAL=$((HEALTH_CHECK_TOTAL + 1))

    if [ "${exit_code}" -eq 0 ]; then
        HEALTH_CHECK_PASSED=$((HEALTH_CHECK_PASSED + 1))
        print_status success "${check_name}"
    else
        HEALTH_CHECK_FAILED=$((HEALTH_CHECK_FAILED + 1))
        print_status error "${check_name}"
        if [ -n "${output}" ] && [ "${MISE_TASK_QUIET_DEFAULT:-false}" != "true" ]; then
            printf '    %s\n' "${output}" | head -3
        fi
    fi

    return "${exit_code}"
}

# Skip a health check with reason
# Arguments:
#   $1 - Check name
#   $2 - Skip reason
skip_health_check() {
    local check_name="${1:-Unknown check}"
    local reason="${2:-Skipped}"

    HEALTH_CHECK_NAMES+=("${check_name}")
    HEALTH_CHECK_RESULTS+=("-1")
    HEALTH_CHECK_OUTPUTS+=("${reason}")
    HEALTH_CHECK_CATEGORIES+=("skipped")
    HEALTH_CHECK_DURATIONS+=("0")

    HEALTH_CHECK_TOTAL=$((HEALTH_CHECK_TOTAL + 1))
    HEALTH_CHECK_SKIPPED=$((HEALTH_CHECK_SKIPPED + 1))

    print_status info "${check_name} (skipped: ${reason})"
}

# Get result for a specific check by name
# Arguments:
#   $1 - Check name
# Output: Exit code of the check
# Returns: 0 if found, 1 if not found
get_health_check_result() {
    local check_name="${1:-}"
    local i

    for i in "${!HEALTH_CHECK_NAMES[@]}"; do
        if [ "${HEALTH_CHECK_NAMES[${i}]}" = "${check_name}" ]; then
            printf '%s' "${HEALTH_CHECK_RESULTS[${i}]}"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# NIX-SPECIFIC HEALTH CHECKS
# =============================================================================

# Check if Nix is installed
check_nix_installed() {
    if command -v nix > /dev/null 2>&1; then
        nix --version
        return 0
    fi
    return 1
}

# Check if Nix daemon is running
check_nix_daemon() {
    if nix store ping > /dev/null 2>&1; then
        return 0
    fi

    # Try to check via systemd on Linux
    if command -v systemctl > /dev/null 2>&1; then
        if systemctl is-active --quiet nix-daemon 2> /dev/null; then
            return 0
        fi
    fi

    # Try launchd on macOS
    if command -v launchctl > /dev/null 2>&1; then
        if launchctl list 2> /dev/null | grep -q org.nixos.nix-daemon; then
            return 0
        fi
    fi

    return 1
}

# Check if flakes are enabled
check_nix_flakes() {
    if nix flake --help > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if flake.nix exists
check_flake_exists() {
    local root="${MISE_PROJECT_ROOT:-${PWD}}"
    if [ -f "${root}/flake.nix" ]; then
        return 0
    fi
    return 1
}

# Check if flake.lock exists
check_flake_lock() {
    local root="${MISE_PROJECT_ROOT:-${PWD}}"
    if [ -f "${root}/flake.lock" ]; then
        return 0
    fi
    return 1
}

# Check if flake evaluates successfully
check_flake_eval() {
    local root="${MISE_PROJECT_ROOT:-${PWD}}"
    if nix flake check "${root}" --no-build > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# =============================================================================
# SYSTEM HEALTH CHECKS
# =============================================================================

# Check available disk space
# Arguments:
#   $1 - Minimum GB required (default: 10)
check_disk_space() {
    local min_gb="${1:-10}"
    local available_kb

    if command -v df > /dev/null 2>&1; then
        # Get available space in KB for /nix or root
        if [ -d "/nix" ]; then
            available_kb=$(df -k /nix 2> /dev/null | tail -1 | awk '{print $4}')
        else
            available_kb=$(df -k / 2> /dev/null | tail -1 | awk '{print $4}')
        fi

        if [ -n "${available_kb}" ]; then
            local available_gb=$((available_kb / 1024 / 1024))
            if [ "${available_gb}" -ge "${min_gb}" ]; then
                printf '%dGB available' "${available_gb}"
                return 0
            else
                printf '%dGB available (need %dGB)' "${available_gb}" "${min_gb}"
                return 1
            fi
        fi
    fi

    return 1
}

# Check network connectivity
check_network() {
    local test_host="${1:-github.com}"
    local timeout=3

    if command -v curl > /dev/null 2>&1; then
        if curl -s --connect-timeout "${timeout}" "https://${test_host}" > /dev/null 2>&1; then
            return 0
        fi
    elif command -v wget > /dev/null 2>&1; then
        if wget -q --timeout="${timeout}" --spider "https://${test_host}" 2> /dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check if Docker is available
check_docker() {
    if command -v docker > /dev/null 2>&1; then
        if docker info > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Check Git configuration
check_git_config() {
    local user_name user_email

    if ! command -v git > /dev/null 2>&1; then
        return 1
    fi

    user_name=$(git config user.name 2> /dev/null)
    user_email=$(git config user.email 2> /dev/null)

    if [ -n "${user_name}" ] && [ -n "${user_email}" ]; then
        printf '%s <%s>' "${user_name}" "${user_email}"
        return 0
    fi

    return 1
}

# =============================================================================
# TERMINAL ENVIRONMENT HEALTH CHECKS
# =============================================================================

# Check if tmux is available and configured
check_tmux() {
    if command -v tmux > /dev/null 2>&1; then
        local version
        version=$(tmux -V 2> /dev/null | head -1)
        printf '%s' "${version}"
        return 0
    fi
    return 1
}

# Check if neovim is available
check_neovim() {
    if command -v nvim > /dev/null 2>&1; then
        local version
        version=$(nvim --version 2> /dev/null | head -1)
        printf '%s' "${version}"
        return 0
    fi
    return 1
}

# Check if tmuxp is available for session management
check_tmuxp() {
    if command -v tmuxp > /dev/null 2>&1; then
        local version
        version=$(tmuxp --version 2> /dev/null | head -1)
        printf '%s' "${version}"
        return 0
    fi
    return 1
}

# =============================================================================
# SUMMARY AND REPORTING
# =============================================================================

# Print health check summary
print_health_summary() {
    print_divider

    local status_text
    if [ "${HEALTH_CHECK_FAILED}" -eq 0 ]; then
        status_text="${GREEN}All checks passed${NC}"
    else
        status_text="${RED}Some checks failed${NC}"
    fi

    printf '\n%b\n' "${status_text}"
    printf '  Total:   %d\n' "${HEALTH_CHECK_TOTAL}"
    printf '  Passed:  %b%d%b\n' "${GREEN}" "${HEALTH_CHECK_PASSED}" "${NC}"
    printf '  Failed:  %b%d%b\n' "${RED}" "${HEALTH_CHECK_FAILED}" "${NC}"
    if [ "${HEALTH_CHECK_SKIPPED}" -gt 0 ]; then
        printf '  Skipped: %b%d%b\n' "${YELLOW}" "${HEALTH_CHECK_SKIPPED}" "${NC}"
    fi

    printf '\n'

    # Return non-zero if any critical checks failed
    local i
    for i in "${!HEALTH_CHECK_NAMES[@]}"; do
        if [ "${HEALTH_CHECK_CATEGORIES[${i}]}" = "critical" ]; then
            if [ "${HEALTH_CHECK_RESULTS[${i}]}" -ne 0 ]; then
                return 1
            fi
        fi
    done

    return 0
}

# Print detailed health report
print_health_report() {
    print_header "Health Check Report"

    local i
    for i in "${!HEALTH_CHECK_NAMES[@]}"; do
        local name="${HEALTH_CHECK_NAMES[${i}]}"
        local result="${HEALTH_CHECK_RESULTS[${i}]}"
        local category="${HEALTH_CHECK_CATEGORIES[${i}]}"
        local duration="${HEALTH_CHECK_DURATIONS[${i}]}"
        local output="${HEALTH_CHECK_OUTPUTS[${i}]}"

        local status_icon
        if [ "${result}" -eq 0 ]; then
            status_icon="${CHECK}"
        elif [ "${result}" -eq -1 ]; then
            status_icon="${WARN}"
        else
            status_icon="${CROSS}"
        fi

        printf '%b %-40s [%s] (%.2fs)\n' "${status_icon}" "${name}" "${category}" "${duration}"

        if [ -n "${output}" ] && [ "${result}" -ne 0 ]; then
            printf '    %s\n' "${output}"
        fi
    done

    print_health_summary
}

# Run all standard health checks
run_standard_health_checks() {
    local quick_mode="${1:-false}"

    print_header "Health Checks"

    # Critical checks
    print_subheader "Critical"
    run_health_check "Nix installed" "check_nix_installed" "critical"
    run_health_check "Nix daemon running" "check_nix_daemon" "critical"
    run_health_check "Flakes enabled" "check_nix_flakes" "critical"

    # Important checks
    print_subheader "Important"
    run_health_check "flake.nix exists" "check_flake_exists" "important"
    run_health_check "flake.lock exists" "check_flake_lock" "important"
    run_health_check "Git configured" "check_git_config" "important"
    run_health_check "Disk space (10GB)" "check_disk_space 10" "important"

    # Terminal environment checks
    print_subheader "Terminal Environment"
    run_health_check "Neovim available" "check_neovim" "important"
    run_health_check "Tmux available" "check_tmux" "important"
    run_health_check "Tmuxp available" "check_tmuxp" "optional"

    # Optional checks (skip in quick mode)
    if [ "${quick_mode}" != "true" ]; then
        print_subheader "Optional"
        run_health_check "Network (GitHub)" "check_network github.com" "optional"
        run_health_check "Docker available" "check_docker" "optional"
        run_health_check "Flake evaluates" "check_flake_eval" "optional"
    fi

    print_health_summary
}
