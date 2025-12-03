#!/usr/bin/env bash
# shellcheck shell=bash
#
# errors.sh - Error handling for BrainCraft.io mise tasks
#
# Provides:
# - Unix-standard error codes (64-113 for custom errors)
# - Context-aware error messages
# - Safe command execution with error capture
# - Bash 3.2 compatibility
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/errors.sh"
#
# Error Code Ranges:
#   0       - Success
#   1       - General error
#   2       - Misuse of shell command
#   64-78   - BSD sysexits.h compatible
#   79-99   - Reserved for future use
#   100-113 - Custom application errors
#
# Shellcheck directives:
# - SC2034: Variables (error codes) are exported for use by sourcing scripts
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# shellcheck disable=SC2034,SC2292

# Guard against multiple sourcing
if [ -n "${_BCIO_ERRORS_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_ERRORS_SOURCED=1

# =============================================================================
# ERROR CODES (BSD sysexits.h compatible + custom)
# =============================================================================

# Standard error codes
readonly ERR_SUCCESS=0
readonly ERR_GENERAL=1
readonly ERR_MISUSE=2

# BSD sysexits.h compatible (64-78)
readonly ERR_USAGE=64        # Command line usage error
readonly ERR_DATAERR=65      # Data format error
readonly ERR_NOINPUT=66      # Cannot open input
readonly ERR_NOUSER=67       # Addressee unknown
readonly ERR_NOHOST=68       # Host name unknown
readonly ERR_UNAVAILABLE=69  # Service unavailable
readonly ERR_SOFTWARE=70     # Internal software error
readonly ERR_OSERR=71        # System error
readonly ERR_OSFILE=72       # Critical OS file missing
readonly ERR_CANTCREAT=73    # Cannot create output file
readonly ERR_IOERR=74        # Input/output error
readonly ERR_TEMPFAIL=75     # Temporary failure
readonly ERR_PROTOCOL=76     # Remote error in protocol
readonly ERR_NOPERM=77       # Permission denied
readonly ERR_CONFIG=78       # Configuration error

# Custom application errors (100-113)
readonly ERR_NIX_NOT_INSTALLED=100
readonly ERR_NIX_DAEMON_DOWN=101
readonly ERR_FLAKE_INVALID=102
readonly ERR_FLAKE_LOCK_MISSING=103
readonly ERR_SHELL_NOT_FOUND=104
readonly ERR_TOOL_MISSING=105
readonly ERR_LINT_FAILED=106
readonly ERR_FORMAT_FAILED=107
readonly ERR_TEST_FAILED=108
readonly ERR_BUILD_FAILED=109
readonly ERR_VALIDATION_FAILED=110
readonly ERR_NETWORK_FAILED=111
readonly ERR_DOCKER_FAILED=112
readonly ERR_GIT_FAILED=113

# =============================================================================
# ERROR CONTEXT TRACKING
# =============================================================================

# Context variables for detailed error reporting
BCIO_ERROR_CONTEXT=""
BCIO_ERROR_FILE=""
BCIO_ERROR_LINE=""
BCIO_ERROR_FUNC=""

# Set error context for better debugging
# Arguments:
#   $1 - Context description
set_error_context() {
    BCIO_ERROR_CONTEXT="${1:-}"
}

# Clear error context
clear_error_context() {
    BCIO_ERROR_CONTEXT=""
    BCIO_ERROR_FILE=""
    BCIO_ERROR_LINE=""
    BCIO_ERROR_FUNC=""
}

# =============================================================================
# ERROR HANDLING FUNCTIONS
# =============================================================================

# Print error message and exit
# Arguments:
#   $1 - Error message
#   $2 - Exit code (default: 1)
die() {
    local message="${1:-An error occurred}"
    local exit_code="${2:-${ERR_GENERAL}}"

    # Use print_status if available, otherwise printf
    if declare -F print_status > /dev/null 2>&1; then
        print_status error "${message}"
    else
        printf '[ERROR] %s\n' "${message}" >&2
    fi

    # Print context if available
    if [ -n "${BCIO_ERROR_CONTEXT}" ]; then
        printf '  Context: %s\n' "${BCIO_ERROR_CONTEXT}" >&2
    fi

    exit "${exit_code}"
}

# Print error message with specific code and exit
# Arguments:
#   $1 - Error code
#   $2 - Error message
die_with_code() {
    local exit_code="${1:-${ERR_GENERAL}}"
    local message="${2:-An error occurred}"

    die "${message}" "${exit_code}"
}

# Assert that the last command succeeded
# Arguments:
#   $1 - Error message if assertion fails
#   $2 - Exit code (default: 1)
assert_success() {
    local last_exit_code=$?
    local message="${1:-Command failed}"
    local exit_code="${2:-${last_exit_code}}"

    if [ "${last_exit_code}" -ne 0 ]; then
        die "${message}" "${exit_code}"
    fi
}

# Run a command and die on failure
# Arguments:
#   $@ - Command to run
run_or_die() {
    "$@" || die "Command failed: $*" "${ERR_GENERAL}"
}

# Run a command and capture output, die on failure
# Arguments:
#   $1 - Variable name to store output
#   $@ - Command to run
# Returns: Command exit code
capture_or_die() {
    local var_name="${1:-}"
    shift

    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    if [ "${exit_code}" -ne 0 ]; then
        printf '%s\n' "${output}" >&2
        die "Command failed: $*" "${exit_code}"
    fi

    # Set variable using eval (bash 3.2 compatible)
    eval "${var_name}=\${output}"
    return "${exit_code}"
}

# =============================================================================
# SAFE EXECUTION FUNCTIONS
# =============================================================================

# Run a command safely, returning exit code without dying
# Arguments:
#   $@ - Command to run
# Returns: Command exit code
# Output: Command output on stdout/stderr
safe_run() {
    "$@"
    return $?
}

# Run a command and capture both output and exit code
# Arguments:
#   $@ - Command to run
# Output: Command output
# Returns: Command exit code
capture_output() {
    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    printf '%s' "${output}"
    return "${exit_code}"
}

# Run a command with timeout
# Arguments:
#   $1 - Timeout in seconds
#   $@ - Command to run
# Returns: Command exit code or 124 on timeout
run_with_timeout() {
    local timeout_secs="${1:-30}"
    shift

    # timeout provided by flake (coreutils)
    timeout "${timeout_secs}" "$@"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate that a command exists
# Arguments:
#   $1 - Command name
#   $2 - Optional error message
validate_command() {
    local cmd="${1:-}"
    local message="${2:-Required command not found: ${cmd}}"

    if ! command -v "${cmd}" > /dev/null 2>&1; then
        die "${message}" "${ERR_TOOL_MISSING}"
    fi
}

# Validate that a file exists
# Arguments:
#   $1 - File path
#   $2 - Optional error message
validate_file() {
    local file="${1:-}"
    local message="${2:-Required file not found: ${file}}"

    if [ ! -f "${file}" ]; then
        die "${message}" "${ERR_NOINPUT}"
    fi
}

# Validate that a directory exists
# Arguments:
#   $1 - Directory path
#   $2 - Optional error message
validate_directory() {
    local dir="${1:-}"
    local message="${2:-Required directory not found: ${dir}}"

    if [ ! -d "${dir}" ]; then
        die "${message}" "${ERR_NOINPUT}"
    fi
}

# Validate that an environment variable is set
# Arguments:
#   $1 - Variable name
#   $2 - Optional error message
validate_env_var() {
    local var_name="${1:-}"
    local message="${2:-Required environment variable not set: ${var_name}}"

    # Use eval for bash 3.2 compatible variable indirection
    local var_value
    eval "var_value=\${${var_name}:-}"

    if [ -z "${var_value}" ]; then
        die "${message}" "${ERR_CONFIG}"
    fi
}

# =============================================================================
# ERROR MESSAGE HELPERS
# =============================================================================

# Get human-readable error message for error code
# Arguments:
#   $1 - Error code
# Output: Error message string
get_error_message() {
    local code="${1:-0}"

    case "${code}" in
        0) printf 'Success' ;;
        1) printf 'General error' ;;
        2) printf 'Misuse of shell command' ;;
        64) printf 'Command line usage error' ;;
        65) printf 'Data format error' ;;
        66) printf 'Cannot open input' ;;
        67) printf 'Addressee unknown' ;;
        68) printf 'Host name unknown' ;;
        69) printf 'Service unavailable' ;;
        70) printf 'Internal software error' ;;
        71) printf 'System error' ;;
        72) printf 'Critical OS file missing' ;;
        73) printf 'Cannot create output file' ;;
        74) printf 'Input/output error' ;;
        75) printf 'Temporary failure' ;;
        76) printf 'Remote error in protocol' ;;
        77) printf 'Permission denied' ;;
        78) printf 'Configuration error' ;;
        100) printf 'Nix not installed' ;;
        101) printf 'Nix daemon not running' ;;
        102) printf 'Invalid flake configuration' ;;
        103) printf 'Flake lock file missing' ;;
        104) printf 'Shell not found' ;;
        105) printf 'Required tool missing' ;;
        106) printf 'Lint check failed' ;;
        107) printf 'Format check failed' ;;
        108) printf 'Test failed' ;;
        109) printf 'Build failed' ;;
        110) printf 'Validation failed' ;;
        111) printf 'Network operation failed' ;;
        112) printf 'Docker operation failed' ;;
        113) printf 'Git operation failed' ;;
        124) printf 'Command timed out' ;;
        126) printf 'Command not executable' ;;
        127) printf 'Command not found' ;;
        128) printf 'Invalid exit argument' ;;
        130) printf 'Interrupted by Ctrl+C' ;;
        *) printf 'Unknown error (code %d)' "${code}" ;;
    esac
}

# Format error for logging
# Arguments:
#   $1 - Error code
#   $2 - Error message
#   $3 - Optional context
# Output: Formatted error string
format_error() {
    local code="${1:-0}"
    local message="${2:-}"
    local context="${3:-}"

    local error_name
    error_name="$(get_error_message "${code}")"

    if [ -n "${context}" ]; then
        printf '[%s] %s: %s (%s)' "${code}" "${error_name}" "${message}" "${context}"
    else
        printf '[%s] %s: %s' "${code}" "${error_name}" "${message}"
    fi
}
