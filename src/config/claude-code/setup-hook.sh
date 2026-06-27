# Konductor Claude Code devshell/CI setup hook.
# Sourced via nativeBuildInputs = [ devshellHook ]. Points the konductor-claude
# harness at the store config dir and loads both plugins, without seeding a
# writable dir (devshell/CI sessions are ephemeral; CLAUDE_CONFIG_DIR at a store
# path is acceptable when the tool only reads it for a one-shot run).
#
# @configDir@, @konductorPlugin@, @practitionerPlugin@ are substituted by
# makeSetupHook at build time.
export CLAUDE_CONFIG_DIR="@configDir@"
export KONDUCTOR_CLAUDE_PLUGIN_DIRS="@konductorPlugin@ @practitionerPlugin@"
