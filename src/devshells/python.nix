# src/devshells/python.nix
# Python development shell
#
# Package composition defined in: ../packages/

{ baseShell, packages, versions, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "python";

  # packages.pythonPackages from ./packages.nix (single source of truth)
  buildInputs = old.buildInputs ++ packages.pythonPackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="python"
    export name="python"

    # Python environment
    export UV_SYSTEM_PYTHON="1"
    export PYTHONDONTWRITEBYTECODE="1"

    # Auto-activate venv if present
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi

    echo "Python ${langs.python.display} ready"
  '';

  env = old.env // {
    UV_SYSTEM_PYTHON = "1";
    PYTHONDONTWRITEBYTECODE = "1";
  };
})
