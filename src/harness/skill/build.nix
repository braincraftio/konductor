{
  pkgs,
  lib,
  definitions,
}:
let
  skills = lib.mapAttrs (
    id:
    { scope, directory }:
    assert lib.assertMsg (builtins.match "[a-z0-9]+(-[a-z0-9]+)*" id != null) "invalid skill ID: ${id}";
    assert lib.assertMsg (builtins.elem scope [
      "project"
      "practitioner"
    ]) "skill ${id}: scope must be project or practitioner";
    {
      inherit scope directory;
    }
  ) definitions;
  directories = lib.mapAttrs (_: skill: skill.directory) skills;
in
{
  inherit skills;
  directory = pkgs.linkFarm "harness-skills" directories;
  scopes = lib.genAttrs [ "project" "practitioner" ] (
    scope:
    pkgs.linkFarm "harness-skills-${scope}" (
      lib.mapAttrs (_: skill: skill.directory) (lib.filterAttrs (_: skill: skill.scope == scope) skills)
    )
  );
}
