# src/config/linters/ansible-lint/default.nix
# Hermetic wrapper for ansible-lint
#
# Config (native YAML, for easy contribution) is a FLOOR, not a ceiling: it is
# injected via -c ONLY when the project has no ansible-lint config of its own.
# When a project ships .ansible-lint.yml / .ansible-lint.yaml / .config/
# ansible-lint.yml (in the cwd or an ancestor), the wrapper runs bare and lets
# ansible-lint's native discovery use the project config — a forced -c would
# REPLACE it (ansible-lint -c does not merge), silently overriding project skips.
# An explicit -c/-config-file in "$@" always wins; the wrapper never double-sets.
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
      # Floor-not-ceiling config resolution. Pass the konductor default via -c
      # ONLY when neither the caller nor the project supplies one.
      inject_config=1

      # 1. Caller already set a config flag → never override it.
      for arg in "$@"; do
        case "$arg" in
          -c | --config-file | -c=* | --config-file=*) inject_config=0; break ;;
        esac
      done

      # 2. Project ships its own config (cwd or any ancestor) → let ansible-lint
      #    discover it natively; injecting -c would replace it.
      if [ "$inject_config" -eq 1 ]; then
        dir=$PWD
        while :; do
          if [ -f "$dir/.ansible-lint.yml" ] || [ -f "$dir/.ansible-lint.yaml" ] \
            || [ -f "$dir/.ansible-lint" ] || [ -f "$dir/.config/ansible-lint.yml" ]; then
            inject_config=0
            break
          fi
          [ "$dir" = "/" ] && break
          dir=$(dirname "$dir")
        done
      fi

      if [ "$inject_config" -eq 1 ]; then
        exec ansible-lint -c "${configFile}/.ansible-lint.yml" "$@"
      else
        exec ansible-lint "$@"
      fi
    '';
  };

  unwrapped = pkgs.ansible-lint;
  inherit configFile;

  meta = {
    description = "Ansible linter";
    configurable = true;
  };
}
