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
  # Default: Opus 4.6 with the 1M-token context window. Opus 4.6 is the one
  # family where this harness's thinking policy (never-adaptive + low effort) is
  # FULLY enforceable — Fable 5 and Sonnet 5 are always-adaptive at the model
  # level and cannot honor CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING. So the default
  # stays on the model that actually respects the policy. The [1m] suffix forces
  # the 1M window on the Anthropic API / pinned providers. `model` is read once at
  # session start; use /model to switch mid-session.
  model = "claude-opus-4-6[1m]";

  # ── Explicit model roster — one pinned ID per family, no implicit aliases. ──
  # availableModels restricts the /model picker to exactly these. It is user-tier
  # here, so it filters the picker but does not constrain the Default option
  # (enforceAvailableModels is managed-settings-only and not shippable from this
  # harness). The ANTHROPIC_DEFAULT_*_MODEL env vars below pin what each alias
  # resolves to so `opus`/`sonnet`/`haiku`/`fable` land on these exact IDs.
  #
  # 1M context: applied where the model supports it AND is not already always-1M.
  #   - claude-opus-4-6[1m]  → 1M forced via suffix
  #   - claude-sonnet-5      → always 1M on the API; suffix is neither needed nor accepted
  #   - claude-fable-5       → always 1M; no suffix
  #   - claude-haiku-4-5     → 200k only, no 1M variant; no suffix
  availableModels = [
    "claude-fable-5"
    "claude-sonnet-5"
    "claude-opus-4-6"
    "claude-haiku-4-5"
  ];

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

    # ── Pin alias → model-ID resolution explicitly (no implicit "latest"). ──
    # Each family alias resolves to exactly the ID in the roster above, with 1M
    # asserted where the model supports it and isn't already always-1M.
    ANTHROPIC_DEFAULT_FABLE_MODEL = "claude-fable-5";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-5";
    ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-6[1m]";
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-haiku-4-5";

    # ── Never adaptive thinking. ──
    # Reverts Opus 4.6 / Sonnet 4.6 to the fixed thinking budget instead of
    # adaptive reasoning. No-op on Fable 5 / Sonnet 5, which are always-adaptive
    # at the model level — the harness ships the preference where it can hold and
    # defaults to Opus 4.6 (see `model` above) where it fully holds.
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
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
