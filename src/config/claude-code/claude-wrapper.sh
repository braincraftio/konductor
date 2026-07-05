#!/usr/bin/env bash
# Konductor-wrapped `claude`. Seeds a writable per-user config dir from the
# read-only store harness, shares auth with the user's personal claude, loads
# the konductor plugins immutably from the store, and dispatches the hermetic
# system prompt per KONDUCTOR_CLAUDE_SYSTEM_PROMPT_* env vars.
#
# Build-time placeholders (substituted by default.nix):
#   @configDir@           store path of the user-tier config dir (linkFarm)
#   @konductorPlugin@     store path of the konductor plugin
#   @practitionerPlugin@  store path of the konductor-practitioner plugin
#   @systemPromptFile@    store path of the hermetic system-prompt.md
#   @claude@              the unwrapped claude-code package
#
# ─── Precedence: CLI flag > env var > hermetic default ──────────────────────
#
# Standard Unix convention, and the same one src/lib/alias-wrappers.nix's grep
# wrapper already follows: an explicit flag on argv is authoritative and is
# never overridden by anything this wrapper asserts. The wrapper does not rely
# on claude's own argv-order flag-merge semantics to make this true — it
# INSPECTS "$@" before deciding what (if anything) to inject, exactly like the
# grep wrapper inspects "$@" before deciding what to translate/pass through.
#
#   1. User passes --system-prompt / --system-prompt-file / \
#      --append-system-prompt / --append-system-prompt-file explicitly on the
#      CLI → wrapper injects NOTHING into that slot; the user's own flag(s)
#      reach claude untouched, exactly as documented in `claude --help`.
#   2. Else, KONDUCTOR_CLAUDE_SYSTEM_PROMPT_{ENABLED,FILE,FILE_MODE} env vars
#      (settable in .envrc / .env for workspace/project scope) assert what the
#      base system prompt should be.
#   3. Else, the hermetic compiled-in @systemPromptFile@ default applies
#      (KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED default: true).
#
# ─── Env vars (used only when the user has not passed the equivalent flag) ──
#
#   KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED = true | false   (default: true)
#     true  → load the hermetic @systemPromptFile@ as the base system prompt.
#     false → do not load it; base becomes "nothing" (pure claude-code default
#             system prompt, unless KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE below
#             supplies one instead).
#
#   KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE = <path>            (default: unset)
#     An additional workspace/project-level system prompt file, independent of
#     ENABLED. Must exist and be readable if set — an unreadable path is a
#     configuration error and hard-fails, never silently skipped.
#
#   KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_MODE = append | replace (default: append)
#     append  → FILE is passed via --append-system-prompt-file, layered after
#               the hermetic default (if ENABLED=true).
#     replace → FILE is passed via --system-prompt-file, substituting for the
#               hermetic default. Contradicts ENABLED=true (replace implies
#               dropping the hermetic base while ENABLED says keep it) — that
#               combination is a hard error, not a guessed precedence.
#
# Dispatch table for the env-var layer (every combination named; deterministic,
# no fallback chains) — applies ONLY when the user has not passed an equivalent
# CLI flag (see step 1 above, which bypasses this table entirely):
#
#   ENABLED  FILE  FILE_MODE  → base system-prompt flags emitted
#   true     unset  —         → --system-prompt-file @systemPromptFile@
#   false    unset  —         → (none — pure claude-code default)
#   true     set    append    → --system-prompt-file @systemPromptFile@
#                               --append-system-prompt-file "${FILE}"
#   true     set    replace   → ERROR: exit 1, contradictory config
#   false    set    append    → --system-prompt-file "${FILE}"
#   false    set    replace   → --system-prompt-file "${FILE}"
set -o errexit -o nounset -o pipefail

: "${HOME:?HOME must be set for konductor-claude}"

claude_bin="@claude@/bin/claude"

# Konductor plugins, loaded immutably from the store every session.
plugin_args=(
  --plugin-dir "@konductorPlugin@"
  --plugin-dir "@practitionerPlugin@"
)

# ─── Detect user-supplied system-prompt flags in "$@" ────────────────────────
# Mirrors src/lib/alias-wrappers.nix's grep wrapper: inspect argv explicitly,
# never assume merge/precedence behavior of the wrapped binary's own parser.
# Stops scanning at a bare "--": tokens after the end-of-options sentinel are
# claude's positional args, not flags, and must not be misread as flags here.
user_has_base_flag=false
user_has_append_flag=false
for arg in "$@"; do
  case "${arg}" in
    --)
      break
      ;;
    --system-prompt | --system-prompt=* | --system-prompt-file | --system-prompt-file=*)
      user_has_base_flag=true
      ;;
    --append-system-prompt | --append-system-prompt=* | --append-system-prompt-file | --append-system-prompt-file=*)
      user_has_append_flag=true
      ;;
    *) ;;
  esac
done

# ─── System prompt dispatch ──────────────────────────────────────────────────
system_prompt_args=()

if [[ "${user_has_base_flag}" = true ]]; then
  # Step 1: user's own base flag is authoritative. Inject nothing for the base
  # slot regardless of env vars — the env-var layer never overrides an
  # explicit flag. An --append-system-prompt* the user also passed rides
  # through in "$@" unmodified; the wrapper adds nothing there either, since
  # the user already fully owns the system-prompt surface for this invocation.
  :
else
  sp_enabled="${KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED:-true}"
  sp_file="${KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE:-}"
  sp_file_mode="${KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_MODE:-append}"

  case "${sp_enabled}" in
    true | false) ;;
    *)
      printf 'konductor-claude: KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED must be "true" or "false", got: %s\n' "${sp_enabled}" >&2
      exit 1
      ;;
  esac

  case "${sp_file_mode}" in
    append | replace) ;;
    *)
      printf 'konductor-claude: KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_MODE must be "append" or "replace", got: %s\n' "${sp_file_mode}" >&2
      exit 1
      ;;
  esac

  if [[ -n "${sp_file}" ]] && [[ ! -r "${sp_file}" ]]; then
    printf 'konductor-claude: KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE is set but not readable: %s\n' "${sp_file}" >&2
    exit 1
  fi

  if [[ "${sp_enabled}" = "true" ]] && [[ -n "${sp_file}" ]] && [[ "${sp_file_mode}" = "replace" ]]; then
    printf 'konductor-claude: contradictory system-prompt config: KONDUCTOR_CLAUDE_SYSTEM_PROMPT_ENABLED=true (keep hermetic default) with KONDUCTOR_CLAUDE_SYSTEM_PROMPT_FILE_MODE=replace (drop it for %s). Set ENABLED=false to replace, or FILE_MODE=append to layer.\n' "${sp_file}" >&2
    exit 1
  fi

  if [[ "${sp_enabled}" = "true" ]]; then
    system_prompt_args+=(--system-prompt-file "@systemPromptFile@")
    if [[ -n "${sp_file}" ]]; then
      # FILE_MODE is append here by construction (replace + ENABLED=true errored above).
      system_prompt_args+=(--append-system-prompt-file "${sp_file}")
    fi
  else
    if [[ -n "${sp_file}" ]]; then
      # ENABLED=false: FILE is the sole base regardless of FILE_MODE — there is
      # no hermetic default to append to or replace, so both modes collapse to
      # the same flag. This collapse is intentional, not a silently dropped mode.
      system_prompt_args+=(--system-prompt-file "${sp_file}")
    fi
    # ENABLED=false, FILE unset: system_prompt_args stays empty — pure
    # claude-code default system prompt, the explicit escape hatch.
  fi
fi

# Step 1 continued: if the user passed only --append-system-prompt* (no base
# flag), the env-var base layer above still applies — appending is additive,
# not exclusive, so a user append composes on top of whatever base the env
# vars (or the hermetic default) established. Nothing further to do here:
# system_prompt_args holds the base, "$@" holds the user's append flag, and
# claude's own parser composes base + append regardless of argv order
# (verified by direct execution against the shipped binary).
: "${user_has_append_flag}" # readability marker; behavior is argv passthrough

# Escape hatch: an explicitly-set CLAUDE_CONFIG_DIR wins (e.g. a user who wants
# their own ~/.claude). --set-default semantics. Plugins and system-prompt
# dispatch still apply; they are orthogonal to the config dir.
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  exec "${claude_bin}" "${plugin_args[@]}" "${system_prompt_args[@]}" "$@"
fi

cfg="${XDG_CONFIG_HOME:-${HOME}/.config}/konductor-claude"
mkdir -p "${cfg}"

# Seed read-only harness content from the store (idempotent). rm before ln so an
# existing real dir/file is replaced, not nested into. ${cfg:?} guards against an
# empty expansion ever targeting /.
for item in settings.json CLAUDE.md rules output-styles statusline-command.sh; do
  rm -rf "${cfg:?}/${item}"
  ln -s "@configDir@/${item}" "${cfg}/${item}"
done

# Share auth with the user's personal claude without sharing config. Dangling
# symlink is intentional: claude materializes ~/.claude.json on first login.
if [[ ! -e "${cfg}/.claude.json" ]]; then
  ln -s "${HOME}/.claude.json" "${cfg}/.claude.json"
fi

export CLAUDE_CONFIG_DIR="${cfg}"
exec "${claude_bin}" "${plugin_args[@]}" "${system_prompt_args[@]}" "$@"
