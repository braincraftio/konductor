#!/bin/sh
# Fix locale issues in container environments
# LC_ALL overrides all locale settings and can cause issues with Nix

# Unset LC_ALL - it's too restrictive
unset LC_ALL 2>/dev/null || true

# Ensure LANG is set (C.UTF-8 is always available in containers)
[ -z "$LANG" ] && export LANG=C.UTF-8

# Set LC_* variables if not already set
[ -z "$LC_CTYPE" ] && export LC_CTYPE="$LANG"
[ -z "$LC_COLLATE" ] && export LC_COLLATE="$LANG"
