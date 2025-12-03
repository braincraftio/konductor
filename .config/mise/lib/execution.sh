#!/usr/bin/env bash
# shellcheck shell=bash
#
# execution.sh - Multi-repository execution framework for BrainCraft.io
#
# Provides:
# - Parallel array-based execution state tracking
# - Multi-repository command orchestration
# - Sequential and parallel execution modes
# - Result aggregation and reporting
# - Bash 3.2 compatibility
#
# Usage:
#   source "${MISE_PROJECT_ROOT}/.config/mise/lib/execution.sh"
#   execute_across_repos "my_function" "true" "false"
#   print_execution_summary
#
# Shellcheck directives:
# - SC1091: Sourced files are validated separately and paths are dynamic
# - SC2034: Variables are exported for use by sourcing scripts
# - SC2154: Variables (colors, symbols) are defined in sourced common.sh
# - SC2292: Using [ ] instead of [[ ]] for Bash 3.2 compatibility (macOS ships 3.2)
# - SC2312: Command substitution in pipelines is intentional for inline processing
# - SC2317: Nested functions are invoked indirectly via execute_across_repos
# shellcheck disable=SC1091,SC2034,SC2154,SC2292,SC2312,SC2317

# Guard against multiple sourcing
if [ -n "${_BCIO_EXECUTION_SOURCED:-}" ]; then
    return 0
fi
readonly _BCIO_EXECUTION_SOURCED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/errors.sh"

# =============================================================================
# EXECUTION STATE (Parallel Arrays for bash 3.2)
# =============================================================================

# State tracking arrays
EXEC_STATE_REPO_NAMES=()
EXEC_STATE_REPO_PATHS=()
EXEC_STATE_RESULTS=()
EXEC_STATE_OUTPUTS=()
EXEC_STATE_DURATIONS=()

# Counters
EXEC_STATE_TOTAL=0
EXEC_STATE_SUCCESS=0
EXEC_STATE_FAILURE=0
EXEC_STATE_SKIPPED=0

# Failed repositories list
EXEC_STATE_FAILED_REPOS=()

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# Reset execution state
reset_execution_state() {
    EXEC_STATE_REPO_NAMES=()
    EXEC_STATE_REPO_PATHS=()
    EXEC_STATE_RESULTS=()
    EXEC_STATE_OUTPUTS=()
    EXEC_STATE_DURATIONS=()
    EXEC_STATE_TOTAL=0
    EXEC_STATE_SUCCESS=0
    EXEC_STATE_FAILURE=0
    EXEC_STATE_SKIPPED=0
    EXEC_STATE_FAILED_REPOS=()
}

# Record execution result
# Arguments:
#   $1 - Repository name
#   $2 - Repository path
#   $3 - Exit code
#   $4 - Output (optional)
#   $5 - Duration (optional)
record_execution_result() {
    local repo_name="${1:-unknown}"
    local repo_path="${2:-}"
    local exit_code="${3:-0}"
    local output="${4:-}"
    local duration="${5:-0}"

    EXEC_STATE_REPO_NAMES+=("${repo_name}")
    EXEC_STATE_REPO_PATHS+=("${repo_path}")
    EXEC_STATE_RESULTS+=("${exit_code}")
    EXEC_STATE_OUTPUTS+=("${output}")
    EXEC_STATE_DURATIONS+=("${duration}")

    EXEC_STATE_TOTAL=$((EXEC_STATE_TOTAL + 1))

    if [ "${exit_code}" -eq 0 ]; then
        EXEC_STATE_SUCCESS=$((EXEC_STATE_SUCCESS + 1))
    elif [ "${exit_code}" -eq -1 ]; then
        EXEC_STATE_SKIPPED=$((EXEC_STATE_SKIPPED + 1))
    else
        EXEC_STATE_FAILURE=$((EXEC_STATE_FAILURE + 1))
        EXEC_STATE_FAILED_REPOS+=("${repo_name}")
    fi
}

# =============================================================================
# REPOSITORY DISCOVERY
# =============================================================================

# Get list of repositories from configuration
# Output: Newline-separated list of "name:path" pairs
list_repositories() {
    local config_path="${MISE_PROJECT_ROOT:-.}/.config/workspace/config.json"

    if [ -f "${config_path}" ] && command -v jq > /dev/null 2>&1; then
        jq -r '.repositories[]? | "\(.name):\(.path)"' "${config_path}" 2> /dev/null
    else
        # Fallback: detect child directories with .git
        local dir
        for dir in "${MISE_PROJECT_ROOT:-.}"/*/; do
            if [ -d "${dir}.git" ]; then
                local name
                name="$(basename "${dir}")"
                printf '%s:%s\n' "${name}" "${dir%/}"
            fi
        done
    fi
}

# Check if a path is a valid repository
# Arguments:
#   $1 - Path to check
# Returns: 0 if valid, 1 otherwise
is_valid_repository() {
    local path="${1:-}"

    [ -n "${path}" ] && [ -d "${path}" ] && [ -d "${path}/.git" ]
}

# =============================================================================
# EXECUTION FUNCTIONS
# =============================================================================

# Execute a function across all repositories
# Arguments:
#   $1 - Function name to execute (receives repo_name and repo_path)
#   $2 - Include workspace root (true/false, default: false)
#   $3 - Quiet mode (true/false, default: false)
execute_across_repos() {
    local execute_func="${1:-}"
    local include_workspace="${2:-false}"
    local quiet="${3:-false}"

    if [ -z "${execute_func}" ]; then
        print_status error "No function specified for execution"
        return 1
    fi

    # Validate function exists
    if ! declare -F "${execute_func}" > /dev/null 2>&1; then
        print_status error "Function not found: ${execute_func}"
        return 1
    fi

    # Reset state
    reset_execution_state

    local start_time end_time duration
    local output exit_code

    # Execute in workspace root if requested
    if [ "${include_workspace}" = "true" ]; then
        local workspace_path="${MISE_PROJECT_ROOT:-${PWD}}"

        if [ "${quiet}" != "true" ]; then
            print_status info "Executing in workspace root..."
        fi

        # Get start time
        start_time=$(date +%s)

        # Execute function
        output=$("${execute_func}" "workspace" "${workspace_path}" 2>&1)
        exit_code=$?

        # Calculate duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        # Record result
        record_execution_result "workspace" "${workspace_path}" "${exit_code}" "${output}" "${duration}"

        if [ "${quiet}" != "true" ]; then
            if [ "${exit_code}" -eq 0 ]; then
                print_status success "workspace"
            else
                print_status error "workspace"
            fi
        fi
    fi

    # Get repositories
    local repos
    repos=$(list_repositories)

    # Execute in each repository
    while IFS= read -r repo_line; do
        [ -z "${repo_line}" ] && continue

        local repo_name="${repo_line%%:*}"
        local repo_path="${repo_line#*:}"

        # Resolve relative paths
        if [ "${repo_path#/}" = "${repo_path}" ]; then
            repo_path="${MISE_PROJECT_ROOT:-${PWD}}/${repo_path}"
        fi

        # Validate repository
        if ! is_valid_repository "${repo_path}"; then
            if [ "${quiet}" != "true" ]; then
                print_status warning "${repo_name} (not a valid repository)"
            fi
            record_execution_result "${repo_name}" "${repo_path}" "-1" "Not a valid repository" "0"
            continue
        fi

        if [ "${quiet}" != "true" ]; then
            print_status info "Executing in ${repo_name}..."
        fi

        # Get start time
        start_time=$(date +%s)

        # Execute function
        output=$("${execute_func}" "${repo_name}" "${repo_path}" 2>&1)
        exit_code=$?

        # Calculate duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        # Record result
        record_execution_result "${repo_name}" "${repo_path}" "${exit_code}" "${output}" "${duration}"

        if [ "${quiet}" != "true" ]; then
            if [ "${exit_code}" -eq 0 ]; then
                print_status success "${repo_name}"
            else
                print_status error "${repo_name}"
                if [ -n "${output}" ]; then
                    printf '    %s\n' "${output}" | head -3
                fi
            fi
        fi
    done <<< "${repos}"

    # Return failure if any execution failed
    [ "${EXEC_STATE_FAILURE}" -eq 0 ]
}

# Execute a command in a specific directory
# Arguments:
#   $1 - Directory path
#   $@ - Command and arguments
# Returns: Command exit code
execute_in_directory() {
    local dir="${1:-}"
    shift

    if [ -z "${dir}" ] || [ ! -d "${dir}" ]; then
        return 1
    fi

    (cd "${dir}" && "$@")
}

# Execute a git command across repositories
# Arguments:
#   $1 - Git command (pull, fetch, status, etc.)
#   $@ - Additional git arguments
execute_git_across_repos() {
    local git_cmd="${1:-status}"
    shift

    # Define the execution function
    _git_executor() {
        local repo_name="${1:-}"
        local repo_path="${2:-}"

        execute_in_directory "${repo_path}" git "${git_cmd}" "$@"
    }

    execute_across_repos "_git_executor" "true" "false"
}

# =============================================================================
# SMART GIT OPERATIONS
# =============================================================================

# Execute git pull with smart handling
# Arguments:
#   $1 - Repository name
#   $2 - Repository path
execute_git_pull() {
    local repo_name="${1:-}"
    local repo_path="${2:-}"

    # Check for commits before pulling
    local has_commits
    has_commits=$(cd "${repo_path}" && git rev-list --count HEAD 2> /dev/null || printf '0')

    if [ "${has_commits}" = "0" ]; then
        printf 'Empty repository - no commits to pull\n'
        return 0
    fi

    # Check for upstream tracking
    local has_upstream
    has_upstream=$(cd "${repo_path}" && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null || printf '')

    if [ -z "${has_upstream}" ]; then
        printf 'No upstream tracking - skipping pull\n'
        return 0
    fi

    # Execute pull
    (cd "${repo_path}" && git pull)
}

# Execute git fetch with smart handling
# Arguments:
#   $1 - Repository name
#   $2 - Repository path
execute_git_fetch() {
    local repo_name="${1:-}"
    local repo_path="${2:-}"

    # Check for remote
    local has_remote
    has_remote=$(cd "${repo_path}" && git remote 2> /dev/null | head -1)

    if [ -z "${has_remote}" ]; then
        printf 'No remote configured - skipping fetch\n'
        return 0
    fi

    # Execute fetch
    (cd "${repo_path}" && git fetch --all --prune)
}

# Execute git status
# Arguments:
#   $1 - Repository name
#   $2 - Repository path
execute_git_status() {
    local repo_name="${1:-}"
    local repo_path="${2:-}"

    (cd "${repo_path}" && git status --short --branch)
}

# =============================================================================
# SUMMARY AND REPORTING
# =============================================================================

# Print execution summary
print_execution_summary() {
    print_divider

    local status_text
    if [ "${EXEC_STATE_FAILURE}" -eq 0 ]; then
        status_text="${GREEN}All executions successful${NC}"
    else
        status_text="${RED}Some executions failed${NC}"
    fi

    printf '\n%b\n' "${status_text}"
    printf '  Total:   %d\n' "${EXEC_STATE_TOTAL}"
    printf '  Success: %b%d%b\n' "${GREEN}" "${EXEC_STATE_SUCCESS}" "${NC}"
    printf '  Failed:  %b%d%b\n' "${RED}" "${EXEC_STATE_FAILURE}" "${NC}"

    if [ "${EXEC_STATE_SKIPPED}" -gt 0 ]; then
        printf '  Skipped: %b%d%b\n' "${YELLOW}" "${EXEC_STATE_SKIPPED}" "${NC}"
    fi

    # List failed repositories
    if [ "${EXEC_STATE_FAILURE}" -gt 0 ]; then
        printf '\n%bFailed repositories:%b\n' "${BOLD}" "${NC}"
        local repo
        for repo in "${EXEC_STATE_FAILED_REPOS[@]}"; do
            printf '  - %s\n' "${repo}"
        done
    fi

    printf '\n'

    # Return non-zero if any failures
    [ "${EXEC_STATE_FAILURE}" -eq 0 ]
}

# Print detailed execution report
print_execution_report() {
    print_header "Execution Report"

    local i
    for i in "${!EXEC_STATE_REPO_NAMES[@]}"; do
        local name="${EXEC_STATE_REPO_NAMES[${i}]}"
        local result="${EXEC_STATE_RESULTS[${i}]}"
        local duration="${EXEC_STATE_DURATIONS[${i}]}"
        local output="${EXEC_STATE_OUTPUTS[${i}]}"

        local status_icon
        if [ "${result}" -eq 0 ]; then
            status_icon="${CHECK}"
        elif [ "${result}" -eq -1 ]; then
            status_icon="${WARN}"
        else
            status_icon="${CROSS}"
        fi

        printf '%b %-30s (%ds)\n' "${status_icon}" "${name}" "${duration}"

        if [ -n "${output}" ] && [ "${result}" -ne 0 ]; then
            printf '    %s\n' "${output}"
        fi
    done

    print_execution_summary
}

# Get failed repositories as space-separated string
get_failed_repos() {
    local result=""
    local repo
    for repo in "${EXEC_STATE_FAILED_REPOS[@]}"; do
        if [ -n "${result}" ]; then
            result="${result} ${repo}"
        else
            result="${repo}"
        fi
    done
    printf '%s' "${result}"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if running in parallel mode is safe
# Returns: 0 if safe, 1 otherwise
can_run_parallel() {
    # Parallel execution requires bash 4+ job control
    # For bash 3.2 compatibility, we default to sequential
    local bash_major="${BASH_VERSION%%.*}"

    [ "${bash_major:-3}" -ge 4 ]
}
