# src/harness/opencode/default.nix
# Konductor OpenCode harness — env vars only, no file writes.
#
# OPENCODE_CONFIG            store path to generated opencode.json
# OPENCODE_CLI_CONFIG_CONTENT native V2 terminal defaults
#
# Skills consume the shared catalog independently of other harnesses.

{
  pkgs,
  lib,
  skill,
  formatters,
  linters,
  languages,
}:

lib.makeExtensible (
  final:
  let
    jsonFmt = pkgs.formats.json { };
    baseConfig = import ./config.nix {
      inherit
        pkgs
        lib
        formatters
        linters
        languages
        ;
    };
    baseTui = import ./tui.nix { };
  in
  {
    config = lib.recursiveUpdate baseConfig {
      skills = [ (builtins.toString skill.directory) ];
      instructions = [ (builtins.toString final.instructionsFile) ];
    };
    tui = baseTui;
    instructionsFile = ./instructions.md;

    configDrv = jsonFmt.generate "opencode.json" final.config;

    tuiDrv = jsonFmt.generate "opencode-cli.json" final.tui;

    # Package composition supplies the same closure used by full developer shells.
    # Explicit Nix overrides rebuild both the wrapper and its configuration.
    wrap =
      runtimeInputs:
      pkgs.writeShellApplication {
        name = "opencode";
        inherit runtimeInputs;
        text = ''
          export PATH=${lib.escapeShellArg (lib.makeBinPath runtimeInputs)}
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: value: ''
              # JSON keys and runtime substitution tokens remain literal.
              # shellcheck disable=SC2016
              export ${name}=${lib.escapeShellArg value}
            '') final.env
          )}
          exec ${lib.getExe pkgs.opencode} "$@"
        '';
        passthru = lib.recursiveUpdate (pkgs.opencode.passthru or { }) {
          unwrapped = pkgs.opencode;
          inherit (final) configDrv tuiDrv;
        };
        meta = lib.recursiveUpdate pkgs.opencode.meta {
          mainProgram = "opencode";
          priority = (pkgs.opencode.meta.priority or lib.meta.defaultPriority) - 1;
        };
      };

    # Consumed by full.nix as ${config.opencode.shellHook}
    shellHook = "";

    # Consumed by full.nix as config.opencode.env
    env = {
      OPENCODE_CONFIG = "${final.configDrv}";
      OPENCODE_CLI_CONFIG_CONTENT = builtins.toJSON final.tui;
      OPENCODE_DISABLE_AUTOUPDATE = "1";
    };

    meta = {
      description = "Konductor OpenCode harness";
      configurable = true;
    };
  }
)
