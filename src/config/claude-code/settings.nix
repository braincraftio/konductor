# src/config/claude-code/settings.nix
# Konductor's shipped settings.json content (a plain attrset; serialized to a
# derivation by formats.json in default.nix — never builtins.toJSON).
#
# This is USER-TIER settings only. Capability content (skills, agents, hooks,
# MCP server definitions) is delivered by the konductor plugins via --plugin-dir,
# NOT through settings.json. settings.json carries model/behavior, permissions,
# the statusline pointer, and enabledPlugins (official LSP marketplace plugins).
#
# Consumers override any leaf via the home-manager module's `settings` option
# (lib.recursiveUpdate onto these defaults) or via .extend. `statusline` flows
# THROUGH final in default.nix so a downstream override recomputes this attrset.

{
  statusline,
}:

{
  # ── Model / behavior — konductor defaults ──
  # Opus 4.6 with the 1M-token context window. The [1m] suffix forces the 1M
  # window on the Anthropic API / pinned providers (it arrives automatically on
  # Max/Team/Enterprise but is harmless to assert). `model` is read once at
  # session start; use /model to switch mid-session.
  model = "claude-opus-4-6[1m]";
  effortLevel = "low";
  alwaysThinkingEnabled = false;
  theme = "dark-daltonized";
  editorMode = "vim";

  # ── Attribution — no Co-Authored-By / PII. Empty strings hide attribution;
  # sessionUrl=false omits the Claude-Session trailer. ──
  attribution = {
    commit = "";
    pr = "";
    sessionUrl = false;
  };

  # ── Git workflow — konductor owns commit/PR conventions via the practitioner
  # git-commit skill, so suppress Claude's built-in git instructions snapshot. ──
  includeGitInstructions = false;

  # NOTE: outputStyle is intentionally UNSET (opt-in via /output-style).

  env = {
    COLORTERM = "truecolor";
  };

  # ── Statusline — absolute store path, hermetic. ──
  statusLine = {
    type = "command";
    command = "${statusline}/bin/claude-statusline";
  };

  # ── Permissions (security surface, defined in permissions.nix) ──
  permissions = import ./permissions.nix;

  # ── Official LSP marketplace plugins (code intelligence). These toggle
  # Anthropic's pre-built LSP plugins; the language-server binaries are provided
  # by ide.nix / languages.nix. Konductor's OWN plugins load via --plugin-dir
  # and are not listed here. ──
  enabledPlugins = {
    "pyright-lsp@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = true;
    "gopls-lsp@claude-plugins-official" = true;
    "rust-analyzer-lsp@claude-plugins-official" = true;
  };
}
