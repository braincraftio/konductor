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
  # Default: Opus 5.5 (always 1M context, no suffix needed). Opus 5.5 is
  # always-adaptive at the model level — CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING
  # is a no-op on it, same as Fable 5 and Sonnet 5. The harness ships the
  # preference where it can hold (Opus 4.6 via the `opus` alias below) but
  # defaults to the strongest available model. `model` is read once at session
  # start; use /model to switch mid-session.
  model = "claude-opus-5-5";

  # ── Explicit model roster — one pinned ID per family, no implicit aliases. ──
  # availableModels restricts the /model picker to exactly these. It is user-tier
  # here, so it filters the picker but does not constrain the Default option
  # (enforceAvailableModels is managed-settings-only and not shippable from this
  # harness). The ANTHROPIC_DEFAULT_*_MODEL env vars below pin what each alias
  # resolves to so `opus`/`sonnet`/`haiku`/`fable` land on these exact IDs.
  #
  # 1M context: applied where the model supports it AND is not already always-1M.
  #   - claude-opus-5-5      → always 1M; no suffix needed
  #   - claude-opus-4-6[1m]  → 1M forced via suffix
  #   - claude-sonnet-5      → always 1M on the API; suffix is neither needed nor accepted
  #   - claude-fable-5       → always 1M; no suffix
  #   - claude-haiku-4-5     → 200k only, no 1M variant; no suffix
  availableModels = [
    "claude-fable-5"
    "claude-sonnet-5"
    "claude-opus-5-5"
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

  # ── Project MCP servers — auto-approve .mcp.json servers in trusted repos.
  # Konductor repos ship .mcp.json (deepwiki, nixos, github, gitea, kubernetes);
  # per-server per-machine approval prompts defeat the hermetic harness. ──
  enableAllProjectMcpServers = true;

  # ── Compaction — manual only. Idle compaction rewrites the conversation while
  # the terminal is unfocused, invalidating the prompt cache on return. Disable
  # it so the cache stays warm across focus switches. /compact remains available. ──
  idleCompaction = false;

  # ── Checkpointing — disabled. /rewind snapshots add write overhead on every
  # file edit. The git history is the checkpoint mechanism for konductor work. ──
  fileCheckpointingEnabled = false;

  # ── Spell checking — aspell (with the en dictionary) ships beside the wrapped
  # claude in src/packages/ai.nix, so every surface that has claude has the
  # checker. Pinned by name: Claude Code does not fall back from a named checker. ──
  spellcheck = {
    enabled = true;
    checker = "aspell";
  };

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

    # ── Never adaptive thinking (where enforceable). ──
    # Reverts Opus 4.6 / Sonnet 4.6 to the fixed thinking budget instead of
    # adaptive reasoning. No-op on Opus 5.5 / Fable 5 / Sonnet 5, which are
    # always-adaptive at the model level. The harness ships the preference for
    # sessions that select Opus 4.6 via the `opus` alias.
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
