#!/usr/bin/env bash
# PreToolUse(Bash) commit guard — helpful, non-blocking.
#
# When a `git commit` is about to run, surface the commit ceremony as advisory
# context (exit 0 always; never blocks). Stays SILENT when the repository
# defines its own contributing/commit convention — in that case the repo's rules
# govern and the user invokes the /git-commit ceremony explicitly to reconcile.
#
# This is the auto-invoke-when-not-in-conflict path: the always-loaded commits
# rule is the baseline; this nudge points at the heavier ceremony only where it
# is helpful and not stepping on a repo's own conventions.
#
# Kill switch (konductor-namespaced, not a Claude Code var):
#   KONDUCTOR_CLAUDE_HOOKS_DISABLE=1

[ "${KONDUCTOR_CLAUDE_HOOKS_DISABLE:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null || true)

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
else
  cmd="$input"
fi
[ -z "$cmd" ] && exit 0

# Only act on git commit invocations.
case "$cmd" in
  *"git commit"*|*"git "*"commit"*) ;;
  *) exit 0 ;;
esac

# Determine repo root; if not in a repo, nothing to advise.
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$root" ] && exit 0

# If the repo defines its own commit convention, stay silent — its rules win and
# the user reconciles via the explicit /git-commit ceremony.
repo_has_convention=0
for f in \
  "$root/CONTRIBUTING.md" "$root/CONTRIBUTING" "$root/.github/CONTRIBUTING.md" \
  "$root/commitlint.config.js" "$root/commitlint.config.cjs" "$root/commitlint.config.mjs" \
  "$root/commitlint.config.ts" "$root/.commitlintrc" "$root/.commitlintrc.json" \
  "$root/.commitlintrc.js" "$root/.commitlintrc.cjs" "$root/.commitlintrc.yml" \
  "$root/.claude/rules/commits.md"; do
  if [ -e "$f" ]; then repo_has_convention=1; break; fi
done
# commitlint config nested under package.json is also a signal.
if [ "$repo_has_convention" -eq 0 ] && [ -f "$root/package.json" ] \
   && command -v jq >/dev/null 2>&1 \
   && jq -e '.commitlint' "$root/package.json" >/dev/null 2>&1; then
  repo_has_convention=1
fi

[ "$repo_has_convention" -eq 1 ] && exit 0

# No conflicting repo convention: nudge toward the ceremony baseline.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Committing: follow the commit convention (conventional commits; objective diff-derived technicals; no narrative; no AI attribution or PII). Read the full staged diff first (git --no-pager diff --staged); never truncate diff output."}}\n'
exit 0
