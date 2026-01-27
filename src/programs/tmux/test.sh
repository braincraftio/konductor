#!/usr/bin/env bash
# k9/src/programs/tmux/test.sh
# Automated test suite for Konductor tmux configuration
# Run from within a konductor devshell: bash src/programs/tmux/test.sh

set -euo pipefail
set -x

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}PASS${NC}"; }
fail() { echo -e "${RED}FAIL${NC}"; exit 1; }
warn() { echo -e "${YELLOW}WARN${NC}"; }

echo "=== Konductor Tmux Test Suite ==="
echo ""

# Test 1: Environment variable KONDUCTOR_TMUX_CONF
echo -n "1. KONDUCTOR_TMUX_CONF env var... "
if [ -n "${KONDUCTOR_TMUX_CONF:-}" ]; then
  if [ -f "$KONDUCTOR_TMUX_CONF" ]; then
    pass
  else
    echo -e "${RED}FAIL${NC} (file not found: $KONDUCTOR_TMUX_CONF)"
    exit 1
  fi
else
  echo -e "${RED}FAIL${NC} (not set)"
  exit 1
fi

# Test 2: Environment variable KONDUCTOR_TMUX_KEYS
echo -n "2. KONDUCTOR_TMUX_KEYS env var... "
if [ -n "${KONDUCTOR_TMUX_KEYS:-}" ]; then
  if [ -f "$KONDUCTOR_TMUX_KEYS" ]; then
    pass
  else
    echo -e "${RED}FAIL${NC} (file not found: $KONDUCTOR_TMUX_KEYS)"
    exit 1
  fi
else
  echo -e "${RED}FAIL${NC} (not set)"
  exit 1
fi

# Test 3: Config syntax validation
echo -n "3. Config syntax validation... "
if tmux -f "$KONDUCTOR_TMUX_CONF" start-server \; kill-server 2>/dev/null; then
  pass
else
  echo -e "${RED}FAIL${NC} (syntax error in config)"
  exit 1
fi

# Test 4: No Tab collision (extrakto should use 'e')
echo -n "4. Extrakto key not tab... "
if ! grep -q '@extrakto_key "tab"' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (extrakto still using tab - collision with last-window)"
  exit 1
fi

# Test 5: Extrakto uses 'e' key
echo -n "5. Extrakto key is 'e'... "
if grep -q '@extrakto_key "e"' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (extrakto key not set to 'e')"
  exit 1
fi

# Test 6: break-pane uses capital B
echo -n "6. break-pane uses 'B' (not 'b')... "
if grep -q 'bind B break-pane' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (break-pane not bound to B)"
  exit 1
fi

# Test 7: send-keys C-b uses lowercase b
echo -n "7. send-keys C-b uses 'b'... "
if grep -q 'bind b send-keys C-b' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (send-keys C-b not bound to b)"
  exit 1
fi

# Test 8: Session persistence plugins configured
echo -n "8. Resurrect plugin configured... "
if grep -q '@resurrect-capture-pane-contents' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (resurrect not configured)"
  exit 1
fi

# Test 9: Continuum plugin configured
echo -n "9. Continuum plugin configured... "
if grep -q '@continuum-save-interval' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (continuum not configured)"
  exit 1
fi

# Test 10: Clipboard tools available (non-fatal)
echo -n "10. Clipboard tools available... "
if command -v xsel >/dev/null 2>&1; then
  echo -e "${GREEN}PASS${NC} (xsel)"
elif command -v wl-copy >/dev/null 2>&1; then
  echo -e "${GREEN}PASS${NC} (wl-copy)"
elif command -v pbcopy >/dev/null 2>&1; then
  echo -e "${GREEN}PASS${NC} (pbcopy)"
else
  warn
  echo "   (no clipboard tool found - clipboard may not work)"
fi

# Test 11: fzf available (required by extrakto and tmux-fzf)
echo -n "11. fzf available... "
if command -v fzf >/dev/null 2>&1; then
  pass
else
  echo -e "${RED}FAIL${NC} (fzf not found - extrakto won't work)"
  exit 1
fi

# Test 12: tmuxp available
echo -n "12. tmuxp available... "
if command -v tmuxp >/dev/null 2>&1; then
  pass
else
  warn
  echo "   (tmuxp not found - session management limited)"
fi

# Test 13: Help keybinding reference content
echo -n "13. Help reference has content... "
if [ -s "$KONDUCTOR_TMUX_KEYS" ]; then
  lines=$(wc -l < "$KONDUCTOR_TMUX_KEYS")
  if [ "$lines" -gt 50 ]; then
    pass
  else
    echo -e "${YELLOW}WARN${NC} (only $lines lines)"
  fi
else
  echo -e "${RED}FAIL${NC} (empty file)"
  exit 1
fi

# Test 14: Alt-1 through Alt-9 bindings present
echo -n "14. Alt-1 through Alt-9 bindings... "
if grep -q 'bind -n M-1 select-window' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'bind -n M-9 select-window' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (direct window access bindings missing)"
  exit 1
fi

# Test 15: Startup message hook
echo -n "15. Startup help message hook... "
if grep -q 'session-created.*display-message.*help' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  warn
  echo "   (startup message hook not found)"
fi

# Test 16: ASCII fallback mode support
echo -n "16. ASCII fallback mode support... "
if grep -q 'KONDUCTOR_ASCII_MODE' "$KONDUCTOR_TMUX_CONF"; then
  # Check for ASCII fallback icons in run-shell commands
  if grep -q '@catppuccin_window_status_style "basic"' "$KONDUCTOR_TMUX_CONF" && \
     grep -q '@catppuccin_session_icon "\[S\]"' "$KONDUCTOR_TMUX_CONF"; then
    pass
  else
    echo -e "${YELLOW}WARN${NC} (ASCII mode detected but icons may be incomplete)"
  fi
else
  echo -e "${RED}FAIL${NC} (ASCII fallback not implemented)"
  exit 1
fi

# Test 17: Rounded window style (modern pill aesthetic)
echo -n "17. Rounded window style... "
if grep -q '@catppuccin_window_status_style "rounded"' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (rounded window style not configured)"
  exit 1
fi

# Test 18: Rounded separator glyphs configured (actual Nerd Font glyphs)
echo -n "18. Rounded separator glyphs... "
# Check that separator lines contain actual UTF-8 bytes for the glyphs
# U+E0B6 = ee 82 b6, U+E0B4 = ee 82 b4
if grep 'status_left_separator' "$KONDUCTOR_TMUX_CONF" | xxd | grep -q 'ee82 b6' && \
   grep 'status_right_separator' "$KONDUCTOR_TMUX_CONF" | xxd | grep -q 'ee82 b4'; then
  pass
else
  echo -e "${RED}FAIL${NC} (rounded separator glyphs not found in config)"
  exit 1
fi

# Test 19: Nested tmux F12 toggle configured
echo -n "19. Nested tmux F12 toggle... "
if grep -q 'bind -T root F12' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'bind -T off F12' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'set prefix None' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'set key-table off' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (nested tmux F12 toggle not configured)"
  exit 1
fi

# Test 20: F12 uses hardcoded colors (not theme variables)
echo -n "20. F12 hardcoded colors... "
# Theme variables like #{@thm_*} don't expand reliably in bind context
if grep -q 'bind -T root F12' "$KONDUCTOR_TMUX_CONF" && \
   ! grep -A5 'bind -T root F12' "$KONDUCTOR_TMUX_CONF" | grep -q '@thm_'; then
  pass
else
  echo -e "${RED}FAIL${NC} (F12 binding uses theme variables - should use hardcoded colors)"
  exit 1
fi

# Test 21: Nested tmux C-b bindings (C-a b and C-a C-b send inner prefix)
echo -n "21. Nested tmux C-b bindings... "
if grep -q 'bind b send-keys C-b' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'bind C-b send-keys C-b' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (nested tmux C-b bindings not configured)"
  exit 1
fi

# Test 22: Catppuccin options use blocking run-shell (NOT async if-shell)
echo -n "22. Catppuccin options use blocking run-shell... "
# CRITICAL: if-shell is async, run-shell blocks. Options must be set before catppuccin loads.
if grep -q 'run-shell.*@catppuccin_status_left_separator' "$KONDUCTOR_TMUX_CONF" && \
   grep -q 'run-shell.*@catppuccin_session_icon' "$KONDUCTOR_TMUX_CONF"; then
  pass
else
  echo -e "${RED}FAIL${NC} (catppuccin options not using blocking run-shell)"
  exit 1
fi

echo ""
echo "=== All critical tests passed ==="
echo ""
echo "To manually verify:"
echo "  1. Start tmux and check theme (Catppuccin Frappe, mauve accent)"
echo "  2. Press prefix + ? to view help"
echo "  3. Press prefix + e for extrakto (NOT prefix + Tab)"
echo "  4. Press prefix + B to break pane (NOT prefix + b)"
echo "  5. Navigate with C-h/j/k/l between tmux and Neovim"
echo "  6. Press prefix + C-s to save session, prefix + C-r to restore"
echo "  7. Test nested tmux: F12 to disable outer, C-a b or C-a C-b for inner prefix"
