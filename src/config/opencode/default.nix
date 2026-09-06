# src/config/opencode/default.nix
# Konductor OpenCode harness — env vars only, no file writes.
#
# OPENCODE_CONFIG_CONTENT  builtins.toJSON inline JSON (store paths propagated via string context)
# OPENCODE_TUI_CONFIG      store path to tui.json (Catppuccin Frappe)
# OPENCODE_DISABLE_*       nix-managed binary and LSP servers
#
# Skills discovered via .claude/skills/ compatibility path (plugin store paths).

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
    commandsDir = ./commands;

    tuiDrv = jsonFmt.generate "opencode-tui.json" final.tui;

    # Consumed by full.nix as ${config.opencode.shellHook}
    shellHook = "";

    # Consumed by full.nix as config.opencode.env
    # builtins.toJSON for env var serialization — store paths from lib.getExe
    # propagate via string context (verified: nixpkgs unstructuredDerivationInputEnv test).
    env = {
      OPENCODE_CONFIG_CONTENT = builtins.toJSON (
        final.config
        // {
          instructions = [ (builtins.toString final.instructionsFile) ];
        }
      );
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
