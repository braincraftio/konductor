#!/usr/bin/env bash
# Konductor-wrapped `claude`. Seeds a writable per-user config dir from the
# read-only store harness, shares auth with the user's personal claude, and
# loads the konductor plugins immutably from the store.
#
# Build-time placeholders (substituted by default.nix):
#   @configDir@           store path of the user-tier config dir (linkFarm)
#   @konductorPlugin@     store path of the konductor plugin
#   @practitionerPlugin@  store path of the konductor-practitioner plugin
#   @claude@              the unwrapped claude-code package
set -o errexit -o nounset -o pipefail

: "${HOME:?HOME must be set for konductor-claude}"

claude_bin="@claude@/bin/claude"

# Konductor plugins, loaded immutably from the store every session.
plugin_args=(
  --plugin-dir "@konductorPlugin@"
  --plugin-dir "@practitionerPlugin@"
)

# Escape hatch: an explicitly-set CLAUDE_CONFIG_DIR wins (e.g. a user who wants
# their own ~/.claude). --set-default semantics. Plugins still load; they are
# orthogonal to the config dir.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  exec "$claude_bin" "${plugin_args[@]}" "$@"
fi

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/konductor-claude"
mkdir -p "$cfg"

# Seed read-only harness content from the store (idempotent). rm before ln so an
# existing real dir/file is replaced, not nested into. ${cfg:?} guards against an
# empty expansion ever targeting /.
for item in settings.json CLAUDE.md rules output-styles statusline-command.sh; do
  rm -rf "${cfg:?}/$item"
  ln -s "@configDir@/$item" "$cfg/$item"
done

# Share auth with the user's personal claude without sharing config. Dangling
# symlink is intentional: claude materializes ~/.claude.json on first login.
if [ ! -e "$cfg/.claude.json" ]; then
  ln -s "$HOME/.claude.json" "$cfg/.claude.json"
fi

export CLAUDE_CONFIG_DIR="$cfg"
exec "$claude_bin" "${plugin_args[@]}" "$@"
