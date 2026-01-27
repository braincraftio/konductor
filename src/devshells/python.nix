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
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs ++ packages.pythonPackages;

  shellHook = old.shellHook + ''
    # Python: activate SSOT venv from UV_PROJECT_ENVIRONMENT (set in .envrc/.env.example)
    if [ -n "$UV_PROJECT_ENVIRONMENT" ] && [ -d "$UV_PROJECT_ENVIRONMENT" ]; then
      source "$UV_PROJECT_ENVIRONMENT/bin/activate" 2>/dev/null || true
    fi

    echo "Python ${langs.python.display} ready"

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Static values in env attribute
  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "python";
    UV_SYSTEM_PYTHON = "1";
    PYTHONDONTWRITEBYTECODE = "1";
  };
})
