# src/config/opencode/default.nix
# Konductor OpenCode harness — env vars only, no file writes.
#
# OPENCODE_CONFIG            store path to generated opencode.json
# OPENCODE_TUI_CONFIG        store path to tui.json
# OPENCODE_DISABLE_*         nix-managed binary and LSP servers
#
# Skills discovered via .claude/skills/ compatibility path.

{ pkgs, lib }:

lib.makeExtensible (
  final:
  let
    jsonFmt = pkgs.formats.json { };
    baseConfig = import ./config.nix { inherit pkgs lib; };
    baseTui = import ./tui.nix { };
  in
  {
    config = baseConfig;
    tui = baseTui;
    instructionsFile = ./instructions.md;

    configDrv = jsonFmt.generate "opencode.json" (
      final.config
      // {
        instructions = [ (builtins.toString final.instructionsFile) ];
      }
    );

    tuiDrv = jsonFmt.generate "opencode-tui.json" final.tui;

    # Consumed by full.nix as ${config.opencode.shellHook}
    shellHook = "";

    # Consumed by full.nix as config.opencode.env
    env = {
      OPENCODE_CONFIG = "${final.configDrv}";
      OPENCODE_TUI_CONFIG = "${final.tuiDrv}";
      OPENCODE_DISABLE_AUTOUPDATE = "1";
      OPENCODE_DISABLE_LSP_DOWNLOAD = "1";
    };

    meta = {
      description = "Konductor OpenCode harness";
      configurable = true;
    };
  }
)
