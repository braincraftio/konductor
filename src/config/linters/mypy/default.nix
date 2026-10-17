# src/config/linters/mypy/default.nix
# Hermetic wrapper for mypy
#
# Config is generated with pkgs.formats.ini. python_version comes from
# src/lib/versions.nix; python_executable points at the shared pythonEnv
# (src/packages/languages.nix) so mypy resolves the same site-packages as the
# devshell interpreter, pyright, and pulumi. mypy itself is built on the pinned
# Python, not the nixpkgs default interpreter.
#
# The wrapper forces config via --config-file flag with no escape hatch.

{
  pkgs,
  versions,
  pythonEnv,
}:

let
  pythonPackages = pkgs.konductor.pythonPackages;
  iniFormat = pkgs.formats.ini { };

  configFile = iniFormat.generate "mypy.ini" {
    mypy = {
      python_version = versions.languages.python.version;
      python_executable = "${pythonEnv}/bin/python";
      warn_return_any = true;
      warn_unused_configs = true;
      disallow_untyped_defs = true;
      disallow_incomplete_defs = true;
      check_untyped_defs = true;
      disallow_any_generics = true;
      no_implicit_optional = true;
      warn_redundant_casts = true;
      warn_unused_ignores = true;
      warn_no_return = true;
      warn_unreachable = true;
      strict_equality = true;
      pretty = true;
      show_error_codes = true;
      show_column_numbers = true;
      show_error_context = true;
      # Discovery honours .gitignore (mypy --exclude-gitignore); the regex is
      # the floor for trees that are never type-checked.
      exclude_gitignore = true;
      exclude = "(^|/)(node_modules|\\.venv|venv|build|dist|_sources|__pycache__|\\.pytest_cache|\\.mypy_cache|\\.ruff_cache)/";
    };

    # Libraries without type information
    "mypy-numpy.*".ignore_missing_imports = true;
    "mypy-pandas.*".ignore_missing_imports = true;
    "mypy-sklearn.*".ignore_missing_imports = true;
    "mypy-scipy.*".ignore_missing_imports = true;
    "mypy-matplotlib.*".ignore_missing_imports = true;
    "mypy-pytest.*".ignore_missing_imports = true;
    "mypy-setuptools.*".ignore_missing_imports = true;

    # Per-module options for gradual adoption
    "mypy-tests.*" = {
      ignore_errors = true;
      disallow_untyped_defs = false;
    };
    "mypy-scripts.*".ignore_errors = true;
  };
in
{
  package = pkgs.writeShellApplication {
    name = "mypy";
    runtimeInputs = [ pythonPackages.mypy ];
    text = ''
      exec mypy --config-file "${configFile}" "$@"
    '';
  };

  unwrapped = pythonPackages.mypy;
  inherit configFile;

  meta = {
    description = "Python type checker";
    configurable = true;
  };
}
