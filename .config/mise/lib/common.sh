#!/usr/bin/env bash
# shellcheck shell=bash
#
# common.sh - Core utilities for BrainCraft.io mise tasks
#
# Provides:
# - Color output with NO_COLOR standard compliance
# - Status printing functions
# - Common utility functions
# - Bash 3.2 compatibility
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/common.sh"
#
# Environment:
#   NO_COLOR     - Disable color output (https://no-color.org/)
#   CI           - Detected CI environment disables color
#   COLORTERM    - Override CI color detection
#   TERM         - Terminal type for capability detection
#
# Shellcheck directives:
# - SC2034: Variables are exported for use by sourcing scripts
# - SC2119: init_colors called without arguments is intentional (uses defaults)
# - SC2120: init_colors accepts optional arguments for --no-color detection
# - SC2249: Case statements intentionally fall through without default handler
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# - SC2312: Command substitution in printf is intentional for inline formatting
# shellcheck disable=SC2034,SC2119,SC2120,SC2249,SC2292,SC2312

# Guard against multiple sourcing
if [ -n "${_BCIO_COMMON_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_COMMON_SOURCED=1

# =============================================================================
# COLOR MANAGEMENT
# =============================================================================

# Check if color output should be used
# Returns: 0 if color should be used, 1 otherwise
should_use_color() {
    # Check for --no-color flag in arguments
    local arg
    for arg in "$@"; do
        if [ "${arg}" = "--no-color" ]; then
            return 1
        fi
    done

    # Respect NO_COLOR environment variable (https://no-color.org/)
    if [ -n "${NO_COLOR:-}" ]; then
        return 1
    fi

    # Disable in CI environments unless COLORTERM is explicitly set
    if [ -n "${CI:-}" ] && [ -z "${COLORTERM:-}" ]; then
        return 1
    fi

    # Check if stdout is a terminal
    if [ ! -t 1 ]; then
        return 1
    fi

    # Check terminal capability
    case "${TERM:-dumb}" in
        dumb | unknown)
            return 1
            ;;
        *)
            # Default: assume color capable
            ;;
    esac

    return 0
}

# Initialize color variables
# Can accept arguments for --no-color detection (passed to should_use_color)
init_colors() {
    if should_use_color "$@"; then
        # ANSI color codes
        NC='\033[0m'
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        CYAN='\033[0;36m'
        GRAY='\033[0;90m'
        BOLD='\033[1m'

        # Status symbols with color
        CHECK="${GREEN}✓${NC}"
        CROSS="${RED}✗${NC}"
        WARN="${YELLOW}⚠${NC}"
        INFO="${BLUE}ℹ${NC}"
        ARROW="${CYAN}→${NC}"
    else
        # No color - empty strings
        NC=''
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        GRAY=''
        BOLD=''

        # Status symbols without color (ASCII fallback)
        CHECK='[OK]'
        CROSS='[FAIL]'
        WARN='[WARN]'
        INFO='[INFO]'
        ARROW='->'
    fi

    # Export for subshells
    export NC RED GREEN YELLOW BLUE MAGENTA CYAN GRAY BOLD
    export CHECK CROSS WARN INFO ARROW
}

# Initialize colors on source (can be re-initialized with arguments)
init_colors

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

# Print a status message with appropriate formatting
# Arguments:
#   $1 - Status type: success, error, warning, info, debug
#   $2 - Message to print
#   $3 - Optional: Additional context
print_status() {
    local status_type="${1:-info}"
    local message="${2:-}"
    local context="${3:-}"

    local prefix=""
    local stream=1  # stdout by default

    case "${status_type}" in
        success | ok | pass)
            prefix="${CHECK}"
            ;;
        error | fail | failure)
            prefix="${CROSS}"
            stream=2  # stderr
            ;;
        warning | warn)
            prefix="${WARN}"
            stream=2  # stderr
            ;;
        info)
            prefix="${INFO}"
            ;;
        debug)
            if [ "${MISE_TASK_QUIET_DEFAULT:-false}" = "true" ]; then
                return 0
            fi
            prefix="${GRAY}[DEBUG]${NC}"
            ;;
        *)
            prefix="${INFO}"
            ;;
    esac

    if [ -n "${context}" ]; then
        message="${message} ${GRAY}(${context})${NC}"
    fi

    if [ "${stream}" -eq 2 ]; then
        printf '%b %s\n' "${prefix}" "${message}" >&2
    else
        printf '%b %s\n' "${prefix}" "${message}"
    fi
}

# Print a section header
# Arguments:
#   $1 - Header text
print_header() {
    local text="${1:-}"
    printf '\n%b%s%b\n' "${BOLD}${BLUE}" "${text}" "${NC}"
    printf '%s\n' "$(printf '%*s' "${#text}" '' | tr ' ' '-')"
}

# Print a subheader
# Arguments:
#   $1 - Subheader text
print_subheader() {
    local text="${1:-}"
    printf '\n%b%s%b\n' "${CYAN}" "${text}" "${NC}"
}

# Print a divider line
print_divider() {
    printf '%s\n' "------------------------------------------------------------"
}

# Print a box with title
# Arguments:
#   $1 - Title text
print_box() {
    local title="${1:-}"
    local width=60
    local padding=$(((width - ${#title} - 2) / 2))

    printf '%b╔' "${BLUE}"
    printf '%*s' "${width}" '' | tr ' ' '═'
    printf '╗%b\n' "${NC}"

    printf '%b║%b' "${BLUE}" "${NC}"
    printf '%*s' "${padding}" ''
    printf '%b%s%b' "${BOLD}" "${title}" "${NC}"
    printf '%*s' "$((width - padding - ${#title}))"   ''
    printf '%b║%b\n' "${BLUE}" "${NC}"

    printf '%b╚' "${BLUE}"
    printf '%*s' "${width}" '' | tr ' ' '═'
    printf '╝%b\n' "${NC}"
}

# Print a table row with label and value
# Arguments:
#   $1 - Label
#   $2 - Value
print_table_row() {
    local label="${1:-}"
    local value="${2:-}"
    printf '  %b%-20s%b %s\n' "${GRAY}" "${label}:" "${NC}" "${value}"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Convert string to uppercase (bash 3.2 compatible)
# Arguments:
#   $1 - String to convert
# Output: Uppercase string
to_uppercase() {
    printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]'
}

# Convert string to lowercase (bash 3.2 compatible)
# Arguments:
#   $1 - String to convert
# Output: Lowercase string
to_lowercase() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

# Check if a command exists
# Arguments:
#   $1 - Command name
# Returns: 0 if exists, 1 otherwise
command_exists() {
    command -v "${1:-}" > /dev/null 2>&1
}

# Check if a function exists
# Arguments:
#   $1 - Function name
# Returns: 0 if exists, 1 otherwise
function_exists() {
    declare -F "${1:-}" > /dev/null 2>&1
}

# Get the project root directory
# Output: Absolute path to project root
get_project_root() {
    if [ -n "${MISE_PROJECT_ROOT:-}" ]; then
        printf '%s' "${MISE_PROJECT_ROOT}"
    elif [ -n "${FLAKE_ROOT:-}" ]; then
        printf '%s' "${FLAKE_ROOT}"
    else
        # Fallback: find directory containing flake.nix
        local dir="${PWD}"
        while [ "${dir}" != "/" ]; do
            if [ -f "${dir}/flake.nix" ]; then
                printf '%s' "${dir}"
                return 0
            fi
            dir="$(dirname "${dir}")"
        done
        printf '%s' "${PWD}"
    fi
}

# Validate that we are in the project root
# Returns: 0 if in project root, 1 otherwise
# NOTE: This check is ONLY needed for bootstrap scenarios outside nix develop.
# In normal operation, mise guarantees MISE_PROJECT_ROOT is correct.
validate_project_root() {
    local root
    root="$(get_project_root)"

    if [ ! -f "${root}/flake.nix" ]; then
        print_status error "Not in a flake project (no flake.nix found)"
        return 1
    fi

    return 0
}

# Get current timestamp in ISO format
# Output: ISO 8601 timestamp
get_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

# Get current timestamp in log format
# Output: Log-friendly timestamp
get_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

# Detect the current platform
# Output: Platform identifier (darwin, linux, wsl, container)
detect_platform() {
    # Check for container first
    if [ -f "/.dockerenv" ] || [ -n "${BRAINCRAFTIO_IN_CONTAINER:-}" ]; then
        printf 'container'
        return 0
    fi

    # Check for WSL
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        printf 'wsl'
        return 0
    fi

    # Check OS type
    case "$(uname -s)" in
        Darwin)
            printf 'darwin'
            ;;
        Linux)
            printf 'linux'
            ;;
        *)
            printf 'unknown'
            ;;
    esac
}

# Detect the current architecture
# Output: Architecture identifier (arm64, x86_64)
detect_arch() {
    local arch
    arch="$(uname -m)"

    case "${arch}" in
        arm64 | aarch64)
            printf 'arm64'
            ;;
        x86_64 | amd64)
            printf 'x86_64'
            ;;
        *)
            printf '%s' "${arch}"
            ;;
    esac
}

# Get the Nix system identifier
# Output: Nix system string (e.g., x86_64-linux, aarch64-darwin)
get_nix_system() {
    local arch platform
    arch="$(detect_arch)"
    platform="$(detect_platform)"

    # Convert to Nix naming
    case "${arch}" in
        arm64)
            arch="aarch64"
            ;;
    esac

    case "${platform}" in
        darwin)
            printf '%s-darwin' "${arch}"
            ;;
        linux | wsl | container)
            printf '%s-linux' "${arch}"
            ;;
        *)
            printf '%s-linux' "${arch}"
            ;;
    esac
}

# =============================================================================
# ENVIRONMENT HELPERS
# =============================================================================

# Check if running in CI environment
# Returns: 0 if in CI, 1 otherwise
is_ci() {
    [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ]
}

# Check if running in interactive mode
# Returns: 0 if interactive, 1 otherwise
is_interactive() {
    case "$-" in
        *i*)
            return 0
            ;;
    esac
    return 1
}

# Check if running in Nix shell
# Returns: 0 if in Nix shell, 1 otherwise
is_nix_shell() {
    [ -n "${IN_NIX_SHELL:-}" ] || [ -n "${BRAINCRAFTIO_SHELL_ACTIVE:-}" ]
}
