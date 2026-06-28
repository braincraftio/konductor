# src/config/linters/ansible-lint/default.nix
# Hermetic wrapper for ansible-lint
#
# Config is maintained in native YAML format (.ansible-lint.yml) for easy
# contribution. The wrapper forces config via -c flag.
#
# ansible-lint imports ansible internals at runtime, so the ansible engine must
# be on PATH. runtimeInputs carries konductor's own ansible-core+httpx
# (ansibleEngine, threaded in from packages/ansible) rather than a second copy,
# keeping a single ansible in the closure.

{
  pkgs,
  ansibleEngine ? null,
  ...
}:

let
  # Config file - native YAML, copied to nix store
  configFile = pkgs.writeTextFile {
    name = "ansible-lint-config";
    destination = "/.ansible-lint.yml";
    text = builtins.readFile ./.ansible-lint.yml;
  };

  # ansible-lint needs ansible-core on PATH. Prefer the engine konductor already
  # ships (ansible-core + httpx); fall back to nixpkgs ansible-core standalone so
  # the wrapper is usable a-la-carte without the ansible package category.
  ansibleOnPath = if ansibleEngine != null then ansibleEngine else pkgs.ansible;
in
{
  package = pkgs.writeShellApplication {
    name = "ansible-lint";
    runtimeInputs = [
      pkgs.ansible-lint
      ansibleOnPath
    ];
    text = ''
      exec ansible-lint -c "${configFile}/.ansible-lint.yml" "$@"
    '';
  };

  unwrapped = pkgs.ansible-lint;
  inherit configFile;

  meta = {
    description = "Ansible linter";
    configurable = true;
  };
}
