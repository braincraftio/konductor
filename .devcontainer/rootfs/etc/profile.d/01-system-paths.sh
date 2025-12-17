#!/bin/sh
# System PATH configuration for Konductor devcontainer
# Nix paths take precedence over system paths

# Base system paths
BASE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Nix paths (primary tooling source)
NIX_PATH="/nix/var/nix/profiles/default/bin"

# User local paths
USER_BIN="$HOME/.local/bin"

# Construct PATH - Nix takes precedence
export PATH="${NIX_PATH}:${USER_BIN}:${BASE_PATH}"

# Additional user paths if they exist
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"
