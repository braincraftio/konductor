#!/usr/bin/env bash
# shellcheck shell=bash
#
# formatting.sh - Output formatting utilities for BrainCraft.io
#
# Provides:
# - Progress indicators
# - Table formatting
# - Summary formatting
# - Bash 3.2 compatible implementations
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/formatting.sh"
#
# Shellcheck directives:
# - SC1091: Sourced files are validated separately and paths are dynamic
# - SC2034: Variables are exported for use by sourcing scripts
# - SC2154: Variables (NC, BOLD, colors, etc.) are defined in sourced common.sh
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# - SC2312: Command substitution in printf is intentional for inline formatting
# shellcheck disable=SC1091,SC2034,SC2154,SC2292,SC2312

# Guard against multiple sourcing
if [ -n "${_BCIO_FORMATTING_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_FORMATTING_SOURCED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

# =============================================================================
# PROGRESS INDICATORS
# =============================================================================

# Print a spinner while a command runs
# Arguments:
#   $1 - Message to display
#   $@ - Command to run
# Note: Only works in interactive terminals
run_with_spinner() {
    local message="${1:-Working}"
    shift

    # Non-interactive: just run the command
    if [ ! -t 1 ]; then
        "$@"
        return $?
    fi

    local pid
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local spin_len=${#spin_chars}
    local i=0

    # Run command in background
    "$@" &
    pid=$!

    # Show spinner
    while kill -0 "${pid}" 2> /dev/null; do
        local spin_char="${spin_chars:${i}:1}"
        printf '\r%s %s' "${spin_char}" "${message}"
        i=$(((i + 1) % spin_len))
        sleep 0.1
    done

    # Wait for command and get exit code
    wait "${pid}"
    local exit_code=$?

    # Clear spinner line
    printf '\r%*s\r' "$((${#message} + 3))"   ''

    return "${exit_code}"
}

# Print a progress bar
# Arguments:
#   $1 - Current value
#   $2 - Total value
#   $3 - Width (default: 40)
print_progress_bar() {
    local current="${1:-0}"
    local total="${2:-100}"
    local width="${3:-40}"

    if [ "${total}" -eq 0 ]; then
        total=1
    fi

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf '\r['
    printf '%*s' "${filled}" '' | tr ' ' '='
    if [ "${filled}" -lt "${width}" ]; then
        printf '>'
        printf '%*s' "$((empty - 1))"   '' | tr ' ' ' '
    fi
    printf '] %3d%%' "${percent}"
}

# =============================================================================
# TABLE FORMATTING
# =============================================================================

# Print a simple table row
# Arguments:
#   $1 - First column (label)
#   $2 - Second column (value)
#   $3 - Column width (default: 30)
print_table_row() {
    local label="${1:-}"
    local value="${2:-}"
    local width="${3:-30}"

    printf '  %-*s %s\n' "${width}" "${label}:" "${value}"
}

# Print a key-value pair with color
# Arguments:
#   $1 - Key
#   $2 - Value
#   $3 - Key color (default: CYAN)
print_kv() {
    local key="${1:-}"
    local value="${2:-}"
    local key_color="${3:-${CYAN}}"

    printf '%b%s%b: %s\n' "${key_color}" "${key}" "${NC}" "${value}"
}

# Print a table header
# Arguments:
#   $@ - Column headers
print_table_header() {
    local header=""
    local separator=""

    for col in "$@"; do
        header="${header}${col}\t"
        separator="${separator}$(printf '%*s' "${#col}" '' | tr ' ' '-')\t"
    done

    printf '%b%s%b\n' "${BOLD}" "${header}" "${NC}"
    printf '%s\n' "${separator}"
}

# =============================================================================
# SUMMARY FORMATTING
# =============================================================================

# Print operation summary
# Arguments:
#   $1 - Operation name
#   $2 - Success count
#   $3 - Failure count
#   $4 - Total count (optional, calculated if not provided)
print_operation_summary() {
    local operation="${1:-Operation}"
    local success="${2:-0}"
    local failure="${3:-0}"
    local total="${4:-$((success + failure))}"

    print_divider
    printf '\n%b%s Summary%b\n' "${BOLD}" "${operation}" "${NC}"
    printf '  Total:   %d\n' "${total}"
    printf '  Success: %b%d%b\n' "${GREEN}" "${success}" "${NC}"

    if [ "${failure}" -gt 0 ]; then
        printf '  Failed:  %b%d%b\n' "${RED}" "${failure}" "${NC}"
    else
        printf '  Failed:  %d\n' "${failure}"
    fi

    printf '\n'
}

# Print lint summary
# Arguments:
#   $1 - Linter name
#   $2 - Exit code
#   $3 - File count
#   $4 - Error count
#   $5 - Warning count
print_lint_summary() {
    local linter="${1:-Linter}"
    local exit_code="${2:-0}"
    local file_count="${3:-0}"
    local error_count="${4:-0}"
    local warning_count="${5:-0}"

    local status_icon
    if [ "${exit_code}" -eq 0 ]; then
        status_icon="${CHECK}"
    else
        status_icon="${CROSS}"
    fi

    printf '%b %-20s ' "${status_icon}" "${linter}"
    printf '(%d files' "${file_count}"

    if [ "${error_count}" -gt 0 ]; then
        printf ', %b%d errors%b' "${RED}" "${error_count}" "${NC}"
    fi

    if [ "${warning_count}" -gt 0 ]; then
        printf ', %b%d warnings%b' "${YELLOW}" "${warning_count}" "${NC}"
    fi

    printf ')\n'
}

# =============================================================================
# LIST FORMATTING
# =============================================================================

# Print a bullet list
# Arguments:
#   $@ - List items
print_bullet_list() {
    local item
    for item in "$@"; do
        printf '  • %s\n' "${item}"
    done
}

# Print a numbered list
# Arguments:
#   $@ - List items
print_numbered_list() {
    local i=1
    local item
    for item in "$@"; do
        printf '  %d. %s\n' "${i}" "${item}"
        i=$((i + 1))
    done
}

# Print a tree-style list
# Arguments:
#   $@ - List items (last item gets └── prefix)
print_tree_list() {
    local items=("$@")
    local count=${#items[@]}
    local i

    for i in "${!items[@]}"; do
        if [ "$((i + 1))" -eq "${count}" ]; then
            printf '  └── %s\n' "${items[${i}]}"
        else
            printf '  ├── %s\n' "${items[${i}]}"
        fi
    done
}

# =============================================================================
# FILE AND PATH FORMATTING
# =============================================================================

# Format a file path for display (shorten if needed)
# Arguments:
#   $1 - File path
#   $2 - Max length (default: 50)
# Output: Formatted path
format_path() {
    local path="${1:-}"
    local max_len="${2:-50}"

    # Replace home directory with ~
    local home="${HOME:-}"
    if [ -n "${home}" ]; then
        path="${path/#${home}/\~}"
    fi

    # Shorten if too long
    local len=${#path}
    if [ "${len}" -gt "${max_len}" ]; then
        local prefix_len=$(((max_len - 3) / 2))
        local suffix_len=$((max_len - 3 - prefix_len))
        path="${path:0:${prefix_len}}...${path:$((len - suffix_len))}"
    fi

    printf '%s' "${path}"
}

# Format file size
# Arguments:
#   $1 - Size in bytes
# Output: Human-readable size
format_size() {
    local size="${1:-0}"

    if [ "${size}" -ge 1073741824 ]; then
        printf '%.1fG' "$(echo "scale=1; ${size}/1073741824" | bc)"
    elif [ "${size}" -ge 1048576 ]; then
        printf '%.1fM' "$(echo "scale=1; ${size}/1048576" | bc)"
    elif [ "${size}" -ge 1024 ]; then
        printf '%.1fK' "$(echo "scale=1; ${size}/1024" | bc)"
    else
        printf '%dB' "${size}"
    fi
}

# =============================================================================
# DURATION FORMATTING
# =============================================================================

# Format duration in seconds to human-readable
# Arguments:
#   $1 - Duration in seconds (can be decimal)
# Output: Formatted duration
format_duration() {
    local duration="${1:-0}"

    # Handle decimal durations
    local seconds="${duration%.*}"
    local decimal="${duration#*.}"
    if [ "${decimal}" = "${duration}" ]; then
        decimal=""
    fi

    if [ -z "${seconds}" ] || [ "${seconds}" -eq 0 ]; then
        if [ -n "${decimal}" ]; then
            printf '0.%ss' "${decimal:0:2}"
        else
            printf '0s'
        fi
        return
    fi

    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ "${hours}" -gt 0 ]; then
        printf '%dh %dm %ds' "${hours}" "${minutes}" "${secs}"
    elif [ "${minutes}" -gt 0 ]; then
        printf '%dm %ds' "${minutes}" "${secs}"
    elif [ -n "${decimal}" ]; then
        printf '%d.%ss' "${secs}" "${decimal:0:2}"
    else
        printf '%ds' "${secs}"
    fi
}

# =============================================================================
# COMMAND OUTPUT FORMATTING
# =============================================================================

# Format command for display
# Arguments:
#   $@ - Command and arguments
# Output: Formatted command string
format_command() {
    local cmd="$*"
    printf '%b$ %s%b' "${GRAY}" "${cmd}" "${NC}"
}

# Print command being executed
# Arguments:
#   $@ - Command and arguments
print_command() {
    printf '\n%b$ %s%b\n' "${GRAY}" "$*" "${NC}"
}

# Indent output from a command
# Arguments:
#   $1 - Number of spaces (default: 2)
# Reads from stdin, writes to stdout
indent_output() {
    local spaces="${1:-2}"
    local prefix
    prefix=$(printf '%*s' "${spaces}" '')

    while IFS= read -r line; do
        printf '%s%s\n' "${prefix}" "${line}"
    done
}
