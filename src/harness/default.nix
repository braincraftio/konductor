{
  pkgs,
  lib,
  formatters,
  linters,
  languages,
  claudeCodeSettings ? { },
  opencodeSettings ? { },
  opencodeCliSettings ? { },
  opencodeEnvironment ? { },
  opencodePackage ? pkgs.opencode,
  # src/config/shell/rtk.nix result when konductor.rtk.enable, else null.
  rtk ? null,
  # One atuin for shells, hooks, MCP, and the OpenCode plugin: hook writers and
  # the history database must agree on schema version (konductor.atuin.package).
  atuin ? pkgs.atuin,
}:
let
  skill = import ./skill { inherit pkgs lib; };
in
{
  inherit skill;
  claude-code =
    (import ./claude-code {
      inherit
        pkgs
        lib
        skill
        atuin
        rtk
        ;
    }).extend
      (_final: prev: { settings = lib.recursiveUpdate prev.settings claudeCodeSettings; });
  opencode =
    (import ./opencode {
      package = opencodePackage;
      inherit
        pkgs
        lib
        skill
        atuin
        rtk
        formatters
        linters
        languages
        ;
    }).extend
      (
        _final: prev: {
          config = lib.recursiveUpdate prev.config opencodeSettings;
          tui = lib.recursiveUpdate prev.tui opencodeCliSettings;
          env = lib.recursiveUpdate prev.env opencodeEnvironment;
        }
      );
}
