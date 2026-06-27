#!/usr/bin/env bash
# Konductor Claude Code statusline — Catppuccin Frappé powerline.
#
# Receives a JSON session blob on stdin from Claude Code (~300ms debounce) and
# prints a single ANSI powerline-styled status row.
#
# Palette: Catppuccin Frappé (matches tmux, k9s, btop, neovim, ttyd, starship).
# Requires a Nerd Font terminal + truecolor (Ghostty, iTerm2, Kitty, WezTerm).
#
# Segments (left → right):
#   [model] [git branch +staged ~modified] [ctx-bar % $cost duration] [style] [agent] [vim]
#
# Dependencies (provided via runtimeInputs in statusline.nix): jq git awk coreutils
#
# shellcheck disable=SC2155  # localized command substitutions are intentional here

set -o pipefail

input=$(cat)

# ── Catppuccin Frappé — truecolor ANSI ────────────────────────────────────
BG_BLUE=$'\033[48;2;140;170;238m'
BG_GREEN=$'\033[48;2;166;209;137m'
BG_YELLOW=$'\033[48;2;229;200;144m'
BG_MAUVE=$'\033[48;2;202;158;230m'
BG_TEAL=$'\033[48;2;129;200;190m'
BG_PEACH=$'\033[48;2;239;159;118m'
FG_BASE=$'\033[38;2;48;52;70m'      # base — text on colored segments
FG_DIM=$'\033[38;2;115;121;148m'    # overlay0 — empty bar portion

FG_BLUE=$'\033[38;2;140;170;238m'
FG_GREEN=$'\033[38;2;166;209;137m'
FG_YELLOW=$'\033[38;2;229;200;144m'
FG_MAUVE=$'\033[38;2;202;158;230m'
FG_TEAL=$'\033[38;2;129;200;190m'
FG_PEACH=$'\033[38;2;239;159;118m'

BOLD=$'\033[1m'
RESET=$'\033[0m'

# ── Nerd Font powerline glyphs ────────────────────────────────────────────
SEP=$''    # right-pointing solid arrow
CAP_L=$''  # left rounded cap
CAP_R=$''  # right rounded cap
CHIP=$''   # microchip
BRANCH=$'' # VCS branch
ROBOT=$''  # robot

# ── Extract all fields in one jq pass (unit-separated) ────────────────────
IFS=$'\x1f' read -r MODEL DIR PCT COST VIM_MODE DURATION_MS STYLE AGENT < <(
  echo "$input" | jq -r '[
    (.model.display_name // "claude"),
    (.workspace.current_dir // .cwd // ""),
    ((.context_window.used_percentage // 0) | floor | tostring),
    ((.cost.total_cost_usd // 0) | tostring),
    (.vim.mode // ""),
    ((.cost.total_duration_ms // 0) | tostring),
    (.output_style.name // "default"),
    (.agent.name // "")
  ] | join("")'
)

model_short=$(echo "$MODEL" | sed -E 's/^global\.anthropic\.//; s/-v[0-9]+$//')

# ── Git status — cached to avoid lag on large repos ───────────────────────
CACHE_KEY=$(printf '%s' "$DIR" | (md5sum 2>/dev/null || md5 2>/dev/null) | cut -d' ' -f1)
CACHE_FILE="${TMPDIR:-/tmp}/konductor-claude-git-${CACHE_KEY}"
CACHE_MAX_AGE=5

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] && return 0
  local now mtime
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
  [ "$((now - mtime))" -gt "$CACHE_MAX_AGE" ]
}

if cache_is_stale; then
  if [ -n "$DIR" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH_NAME=$(git -C "$DIR" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    printf '1|%s|%s|%s\n' "$BRANCH_NAME" "$STAGED" "$MODIFIED" >"$CACHE_FILE"
  else
    printf '0|||\n' >"$CACHE_FILE"
  fi
fi
IFS='|' read -r IS_GIT BRANCH_NAME STAGED MODIFIED <"$CACHE_FILE"

# ── Context bar (heavy filled, light empty) ───────────────────────────────
FILLED=$((PCT * 10 / 100))
EMPTY=$((10 - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR="${FG_BASE}$(printf "%${FILLED}s" | tr ' ' '━')"
[ "$EMPTY" -gt 0 ] && BAR="${BAR}${FG_DIM}$(printf "%${EMPTY}s" | tr ' ' '─')"
BAR="${BAR}${FG_BASE}"

COST_FMT=$(awk -v c="$COST" 'BEGIN { printf "$%.2f", c+0 }')
DURATION_FMT=$(awk -v ms="$DURATION_MS" 'BEGIN {
  s = int(ms/1000); m = int(s/60); h = int(m/60)
  if (h > 0) printf "%dh%dm", h, m%60; else printf "%dm", m
}')

# ── Git segment color reflects dirty state ────────────────────────────────
GIT_BG="$BG_GREEN"; GIT_FG="$FG_GREEN"
if [ "${IS_GIT:-0}" = "1" ]; then
  if [ "${STAGED:-0}" -gt 0 ] || [ "${MODIFIED:-0}" -gt 0 ]; then
    GIT_BG="$BG_YELLOW"; GIT_FG="$FG_YELLOW"
  fi
fi

VIM_BG="$BG_GREEN"; VIM_FG="$FG_GREEN"
[ "$VIM_MODE" = "NORMAL" ] && { VIM_BG="$BG_YELLOW"; VIM_FG="$FG_YELLOW"; }

# ── Build the line ────────────────────────────────────────────────────────
LINE="${RESET}${FG_BLUE}${CAP_L}${BG_BLUE}${FG_BASE}${BOLD} ${CHIP} ${model_short} "
LAST_FG="$FG_BLUE"

if [ "${IS_GIT:-0}" = "1" ]; then
  GIT_TEXT="${BRANCH} ${BRANCH_NAME}"
  [ "${STAGED:-0}" -gt 0 ] && GIT_TEXT="${GIT_TEXT} +${STAGED}"
  [ "${MODIFIED:-0}" -gt 0 ] && GIT_TEXT="${GIT_TEXT} ~${MODIFIED}"
  LINE="${LINE}${LAST_FG}${GIT_BG}${SEP}${FG_BASE}${BOLD} ${GIT_TEXT} "
  LAST_FG="$GIT_FG"
fi

LINE="${LINE}${LAST_FG}${BG_MAUVE}${SEP}${FG_BASE}${BOLD} ${BAR} ${PCT}% ${COST_FMT} ${DURATION_FMT} "
LAST_FG="$FG_MAUVE"

if [ -n "$STYLE" ] && [ "$STYLE" != "default" ]; then
  LINE="${LINE}${LAST_FG}${BG_TEAL}${SEP}${FG_BASE}${BOLD} ${STYLE} "
  LAST_FG="$FG_TEAL"
fi

if [ -n "$AGENT" ]; then
  LINE="${LINE}${LAST_FG}${BG_PEACH}${SEP}${FG_BASE}${BOLD} ${ROBOT} ${AGENT} "
  LAST_FG="$FG_PEACH"
fi

if [ -n "$VIM_MODE" ]; then
  LINE="${LINE}${LAST_FG}${VIM_BG}${SEP}${FG_BASE}${BOLD} ${VIM_MODE} "
  LAST_FG="$VIM_FG"
fi

LINE="${LINE}${RESET}${LAST_FG}${CAP_R}${RESET}"
printf '%s\n' "$LINE"
