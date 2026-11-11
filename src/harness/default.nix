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
}:
let
  skill = import ./skill { inherit pkgs lib; };
in
{
  inherit skill;
  claude-code = (import ./claude-code { inherit pkgs lib skill; }).extend (
    _final: prev: { settings = lib.recursiveUpdate prev.settings claudeCodeSettings; }
  );
  opencode =
    (import ./opencode {
      package = opencodePackage;
      inherit
        pkgs
        lib
        skill
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
