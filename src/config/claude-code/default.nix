# src/config/claude-code/default.nix
# Konductor Claude Code harness — complete, hermetic, collision-resistant.
#
# Two delivery channels, one wrapper:
#
#   1. USER-TIER config (settings.json, CLAUDE.md, rules, output-styles,
#      statusline) → a content-addressed linkFarm (configDirDrv). The wrapper
#      seeds a WRITABLE per-user dir (~/.config/konductor-claude), symlinks this
#      read-only content in, and points CLAUDE_CONFIG_DIR at the writable dir.
#
#   2. CAPABILITY content (skills, agents, hooks, MCP/LSP server defs) → two
#      namespaced PLUGINS loaded immutably from the store via `--plugin-dir`:
#        konductor              → /konductor:*              (project)
#        konductor-practitioner → /konductor-practitioner:* (general)
#      Plugins own their own hooks (${CLAUDE_PLUGIN_ROOT}), .mcp.json, .lsp.json.
#
#   3. SYSTEM PROMPT (system-prompt.md, an immutable store path) → dispatched by
#      the wrapper via --system-prompt-file / --append-system-prompt-file,
#      gated by KONDUCTOR_CLAUDE_SYSTEM_PROMPT_{ENABLED,FILE,FILE_MODE} env vars
#      read at wrapper runtime (not build time — set them in .envrc / .env for
#      per-workspace override). Full dispatch table in claude-wrapper.sh. A
#      user's own --system-prompt[-file] / --append-system-prompt[-file] on the
#      CLI always remains live and always composes after the wrapper's own
#      flags in argv (last --system-prompt wins; --append-system-prompt is
#      additive regardless of order — verified against the shipped claude
#      binary, not assumed).
#
# Why a writable seed dir instead of CLAUDE_CONFIG_DIR=<store path> directly:
#   Claude WRITES to CLAUDE_CONFIG_DIR (.claude.json oauth, sessions/, plans/,
#   caches). A read-only /nix/store path fails on first write with EACCES (the
#   same class of bug as cloud-init skel symlinks).
#
# Collision resistance:
#   Dedicated ~/.config/konductor-claude — never touches the user's ~/.claude.
#   Auth is shared via a ~/.claude.json symlink (no re-login); config stays
#   konductor-owned. Capabilities are plugin-namespaced, so /konductor:pulumi
#   can never collide with a user's /pulumi.
#
# Consumers (one wrapper, five contexts):
#   home-manager / qcow2 VM / OCI container / nixos / darwin → install `package`
#   devshell / CI → nativeBuildInputs = [ devshellHook ]  (exports CLAUDE_CONFIG_DIR)
#
# lib.makeExtensible exposes every sub-concern and derived derivation so
# downstream flakes can .extend any layer and have derivations recompute.

{ pkgs, lib }:

lib.makeExtensible (
  final:
  let
    jsonFmt = pkgs.formats.json { };

    statusline = import ./statusline.nix { inherit pkgs; };

    # settings.json content. statusline flows THROUGH final so a downstream
    # .extend on it recomputes settings → settingsDrv → configDirDrv.
    baseSettings = import ./settings.nix {
      statusline = final.statusline;
    };
  in
  {
    # =========================================================================
    # Overlay-able data (downstream .extend targets)
    # =========================================================================
    settings = baseSettings;
    statusline = statusline;

    # =========================================================================
    # Plugin derivations (immutable store copies, loaded via --plugin-dir).
    # Source dirs coerce to store paths.
    # =========================================================================
    konductorPlugin = ./plugins/konductor;
    practitionerPlugin = ./plugins/konductor-practitioner;

    # =========================================================================
    # Hermetic system prompt (immutable store path, loaded via
    # --system-prompt-file / --append-system-prompt-file by the wrapper).
    # Runtime on/off/layering is controlled by KONDUCTOR_CLAUDE_SYSTEM_PROMPT_*
    # env vars read in claude-wrapper.sh — see that file's header for the full
    # dispatch table. This derivation only fixes the CONTENT hermetically; the
    # wrapper fixes the DISPATCH deterministically.
    # =========================================================================
    systemPromptFile = ./system-prompt.md;

    # =========================================================================
    # Derived derivations — ALL reference final.* so .extend propagates, and
    # ALL are exposed for a-la-carte downstream consumption.
    # =========================================================================

    # settings.json — formats.json gives a real derivation, jq pretty-print,
    # cacheable, and $schema for editor validation.
    settingsDrv = jsonFmt.generate "claude-settings.json" (
      final.settings // { "$schema" = "https://json.schemastore.org/claude-code-settings.json"; }
    );

    # USER-TIER config dir (no skills/agents/hooks/mcp — those are plugins).
    # Scripts use lib.getExe → ${drv}/bin/<mainProgram>, never the bare drv dir.
    configDirDrv = pkgs.linkFarm "konductor-claude-config" {
      "settings.json" = final.settingsDrv;
      "CLAUDE.md" = ./context.md;
      "rules" = ./rules;
      "output-styles" = ./output-styles;
      "statusline-command.sh" = lib.getExe final.statusline;
    };

    # Devshell / CI consumer: nativeBuildInputs = [ devshellHook ].
    # makeSetupHook substitutes @configDir@ / @plugin*@ / @systemPromptFile@ in
    # the separate .sh file.
    devshellHook = pkgs.makeSetupHook {
      name = "konductor-claude-code-hook";
      substitutions = {
        configDir = final.configDirDrv;
        konductorPlugin = final.konductorPlugin;
        practitionerPlugin = final.practitionerPlugin;
        systemPromptFile = final.systemPromptFile;
      };
    } ./setup-hook.sh;

    # =========================================================================
    # The wrapped `claude` CLI — the binary konductor ships.
    # =========================================================================
    # The wrapper is a REAL bash file (./claude-wrapper.sh) with @placeholders@,
    # slurped and substituted at build time — not bash embedded in a Nix string.
    # A plain wrapper script (not wrapProgram) because the seeding logic — mkdir,
    # per-item symlink refresh, auth passthrough — cannot be expressed as
    # wrapProgram flags. Defense-in-depth layers, each guarding a distinct,
    # historically-real failure:
    #   - HOME:? guard            → container with no $HOME
    #   - early exec on preset    → --set-default semantics; power-user override
    #   - ${cfg:?} + rm before ln → never target /, replace not nest
    #   - writable seed dir       → EACCES on store-path writes
    #   - ~/.claude.json passthru → shared auth, no re-login, dangling-ok
    #   - --plugin-dir store path → immutable, zero-install plugin load
    #   - system prompt dispatch  → deterministic ENABLED/FILE/FILE_MODE table,
    #                               hard-errors on the ENABLED=true + MODE=replace
    #                               contradiction rather than guessing a winner
    #   - inherit passthru/meta   → keep updateScript, unfree license, platforms
    wrappedClaude =
      pkgs.runCommand "claude"
        {
          nativeBuildInputs = [ pkgs.shellcheck ];
          # substituteAll replaces @name@ with these (paths coerce to store paths).
          configDir = final.configDirDrv;
          konductorPlugin = final.konductorPlugin;
          practitionerPlugin = final.practitionerPlugin;
          systemPromptFile = final.systemPromptFile;
          claude = pkgs.unstable.claude-code;

          passthru = (pkgs.unstable.claude-code.passthru or { }) // {
            unwrapped = pkgs.unstable.claude-code;
            configDir = final.configDirDrv;
            settings = final.settingsDrv;
            konductorPlugin = final.konductorPlugin;
            practitionerPlugin = final.practitionerPlugin;
            systemPromptFile = final.systemPromptFile;
            devshellHook = final.devshellHook;
            extend = final.extend;
          };

          meta = (pkgs.unstable.claude-code.meta or { }) // {
            mainProgram = "claude";
            description = "Konductor-wrapped Claude Code CLI (hermetic ~/.config/konductor-claude harness + plugins)";
          };
        }
        ''
          install -Dm755 ${./claude-wrapper.sh} "$out/bin/claude"
          substituteAllInPlace "$out/bin/claude"
          shellcheck "$out/bin/claude"
        '';

    # The package consumers install (home.packages / systemPackages / ai.nix).
    package = final.wrappedClaude;

    meta = {
      description = "Konductor Claude Code harness";
      configurable = true;
    };
  }
)
