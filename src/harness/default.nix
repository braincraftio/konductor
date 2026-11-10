{
  pkgs,
  lib,
  claudeCodeSettings ? { },
}:
let
  skill = import ./skill { inherit pkgs lib; };
in
{
  inherit skill;
  claude-code = (import ./claude-code { inherit pkgs lib skill; }).extend (
    _final: prev: { settings = lib.recursiveUpdate prev.settings claudeCodeSettings; }
  );
  opencode = import ./opencode { inherit pkgs lib skill; };
}
