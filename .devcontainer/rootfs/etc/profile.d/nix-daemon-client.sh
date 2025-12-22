#!/bin/sh
# shellcheck disable=SC2292
# Set NIX_REMOTE for user sessions only
# CRITICAL: Never set for system services (prevents nix-daemon fork bomb)

# Set NIX_REMOTE for:
# - Non-root users
# - Root via sudo (SUDO_USER set)
# - Interactive sessions (PS1 set)
if [ "${UID}" != "0" ] || [ -n "${SUDO_USER}" ] || [ -n "${PS1}" ]; then
    export NIX_REMOTE=daemon
fi
