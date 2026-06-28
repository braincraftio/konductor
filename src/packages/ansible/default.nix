# src/packages/ansible/default.nix
# Ansible toolchain — engine + linter, shipped as one category.
#
# ansible-core gains httpx via its extraPackages parameter (the designed
# extension seam); toPythonApplication exposes the `ansible` command set as an
# application rather than a Python library. httpx is the HTTP client used by
# API-driven collections.
#
# ansible-lint ships HERE, with the engine, so a shell that has ansible also has
# its linter (the linter is useless without the engine, and the engine is a
# full-shell-only addition). Per the repo invariant the linter's hermetic config
# and wrapper are authored under src/config/linters/ansible-lint/ (native YAML,
# config-forced); this category only composes that wrapper onto the package list
# and threads in the engine so a single ansible lands in the closure.
#
# yamllint remains the linters category's concern. Project-specific collection
# vendoring (ANSIBLE_COLLECTIONS_PATH content) is the consuming project's
# responsibility, not konductor's.

{ pkgs, lib }:

let
  python3Packages = pkgs.python3Packages;

  ansibleWithHttpx = python3Packages.toPythonApplication (
    python3Packages.ansible-core.override {
      extraPackages = ps: [ ps.httpx ];
    }
  );

  # Hermetic ansible-lint wrapper (config authored under src/config/). The
  # wrapper needs ansible on PATH at runtime; pass this category's own engine so
  # the closure carries one ansible, not two.
  ansibleLint = import ../../config/linters/ansible-lint {
    inherit pkgs;
    ansibleEngine = ansibleWithHttpx;
  };
in
{
  # Category package list (composed in packages/default.nix → fullPackages).
  packages = [
    ansibleWithHttpx
    ansibleLint.package
  ];

  # The ansible command set on its own, for a-la-carte consumers.
  package = ansibleWithHttpx;

  # The wrapped ansible-lint on its own, for a-la-carte consumers.
  lint = ansibleLint.package;

  # Unwrapped ansible-core for reference.
  unwrapped = python3Packages.ansible-core;

  shellHook = "";
  env = { };

  meta = {
    description = "ansible-core (with httpx) plus the hermetic ansible-lint wrapper";
  };
}
