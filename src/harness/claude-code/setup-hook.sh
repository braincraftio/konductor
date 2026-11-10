# Konductor Claude Code devshell/CI setup hook.
# Sourced via nativeBuildInputs = [ devshellHook ]. Points the konductor-claude
# harness at the store config dir and loads both plugins, without seeding a
# writable dir (devshell/CI sessions are ephemeral; CLAUDE_CONFIG_DIR at a store
# path is acceptable when the tool only reads it for a one-shot run).
#
# @configDir@, @konductorPlugin@, @practitionerPlugin@, @systemPromptFile@ are
# substituted by makeSetupHook at build time.
export CLAUDE_CONFIG_DIR="@configDir@"
export KONDUCTOR_CLAUDE_PLUGIN_DIRS="@konductorPlugin@ @practitionerPlugin@"

# Hermetic system prompt store path. This hook only exports the CONTENT path;
# it does not assemble --system-prompt-file/--append-system-prompt-file argv
# (unlike the wrapped `claude` binary's claude-wrapper.sh, this devshell path
# has no argv to inject into — it is consumed by whatever invokes `claude`
# directly in the shell). Set KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED=false in
# .envrc/.env to opt out; a devshell caller wiring its own claude invocation
# should read that var and $KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_HERMETIC itself
# (default: true / this store path — same on/off semantics as the wrapper, see
# claude-wrapper.sh's dispatch table for the full ENABLED/FILE/FILE_MODE
# contract this mirrors).
export KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_HERMETIC="@systemPromptFile@"
