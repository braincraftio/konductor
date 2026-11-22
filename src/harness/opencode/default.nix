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
  atuin,
  rtk ? null,
  formatters,
  linters,
  languages,
  package ? pkgs.opencode,
}:

lib.makeExtensible (
  final:
  let
    jsonFmt = pkgs.formats.json { };
    baseConfig = import ./config.nix {
      inherit
        pkgs
        lib
        atuin
        formatters
        linters
        languages
        ;
    };
    baseTui = import ./tui.nix { };
    navigation = import ./navigation.nix { inherit pkgs lib; };
  in
  {
    # Atuin's OpenCode 2 server plugin, taken from the source of the atuin
    # package in use so its `atuin history start/end` flags match the binary.
    # `atuin hook install opencode` would write the same file into
    # ~/.config/opencode/plugins; the store directory replaces that mutation.
    # The plugin spawns `atuin` by name, which the wrapper's runtime PATH provides.
    atuinPlugin = pkgs.runCommand "konductor-opencode-atuin-plugin" { } ''
      install -Dm644 ${atuin.src}/crates/atuin-common/res/harnesstools/opencode/atuin.v2.ts "$out/atuin.ts"
      install -Dm644 ${
        jsonFmt.generate "package.json" {
          name = "konductor-atuin";
          inherit (atuin) version;
          type = "module";
          exports."./server" = "./atuin.ts";
        }
      } "$out/package.json"
    '';

    # rtk's OpenCode plugin from the source of the rtk package in use. It
    # delegates to `rtk hook opencode`, which reads OpenCode's rules from
    # OPENCODE_CONFIG and answers no rewrite whenever the rewritten command
    # would get a different verdict, so the shell rules need no `rtk *` mirror.
    rtkPlugin =
      if rtk == null then
        null
      else
        pkgs.runCommand "konductor-opencode-rtk-plugin" { } ''
          install -Dm644 ${rtk.package.src}/hooks/opencode/rtk.ts "$out/rtk.ts"
          install -Dm644 ${
            jsonFmt.generate "package.json" {
              name = "konductor-rtk";
              inherit (rtk.package) version;
              type = "module";
              exports."./server" = "./rtk.ts";
            }
          } "$out/package.json"
        '';

    config = lib.recursiveUpdate baseConfig {
      skills = [ (builtins.toString skill.directory) ];
      instructions = [
        (builtins.toString final.instructionsFile)
      ]
      ++ lib.optional (rtk != null) (builtins.toString ../rtk.md);
      # rtk before Atuin: Atuin pairs its execute.before proposal with
      # shell create.before by exact command text, so it must see the command
      # after rtk's rewrite or the call is never recorded. Atuin then records
      # `rtk <cmd>`.
      plugins = lib.optional (final.rtkPlugin != null) (builtins.toString final.rtkPlugin) ++ [
        (builtins.toString final.atuinPlugin)
      ];
    };
    tui = lib.recursiveUpdate baseTui {
      plugins = [
        {
          package = builtins.toString ./navigation;
          options.helper = lib.getExe navigation;
        }
      ];
    };
    instructionsFile = ./instructions.md;

    configDrv = jsonFmt.generate "opencode.json" final.config;

    tuiDrv = jsonFmt.generate "opencode-cli.json" final.tui;

    # Package composition supplies the same closure used by full developer shells.
    # Explicit Nix overrides rebuild both the wrapper and its configuration.
    wrap =
      runtimeInputs:
      pkgs.writeShellApplication {
        name = "opencode";
        # writeShellApplication prepends these while preserving the caller's PATH.
        inherit runtimeInputs;
        text = ''
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: value: ''
              # JSON keys and runtime substitution tokens remain literal.
              # shellcheck disable=SC2016
              export ${name}=${lib.escapeShellArg value}
            '') final.env
          )}
          exec ${lib.getExe package} "$@"
        '';
        passthru = lib.recursiveUpdate (package.passthru or { }) {
          unwrapped = package;
          inherit (final) configDrv tuiDrv;
        };
        meta = lib.recursiveUpdate package.meta {
          mainProgram = "opencode";
          priority = (package.meta.priority or lib.meta.defaultPriority) - 1;
        };
      };

    # Consumed by full.nix as ${config.opencode.shellHook}
    shellHook = "";

    # Consumed by full.nix as config.opencode.env
    # RTK_BIN pins the plugin's binary lookup when rtk is not first on PATH.
    env =
      lib.recursiveUpdate
        (lib.optionalAttrs (rtk != null) (
          lib.recursiveUpdate rtk.env { RTK_BIN = lib.getExe rtk.package; }
        ))
        {
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
