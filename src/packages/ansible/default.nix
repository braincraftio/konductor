# src/packages/ansible/default.nix
# General Ansible engine.
#
# ansible-core gains httpx via its extraPackages parameter (the designed
# extension seam); toPythonApplication exposes the `ansible` command set as an
# application rather than a Python library. httpx is the HTTP client used by
# API-driven collections.
#
# Engine only. yamllint and ansible-lint are provided by the linters category
# (config/linters/*, wrapped with hermetic configs); they are not re-added here.
# Project-specific collection vendoring (ANSIBLE_COLLECTIONS_PATH content) is the
# consuming project's responsibility, not konductor's.

{ pkgs, lib }:

let
  python3Packages = pkgs.python3Packages;

  ansibleWithHttpx = python3Packages.toPythonApplication (
    python3Packages.ansible-core.override {
      extraPackages = ps: [ ps.httpx ];
    }
  );
in
{
  # Category package list (composed in packages/default.nix).
  packages = [ ansibleWithHttpx ];

  # The ansible command set on its own, for a-la-carte consumers.
  package = ansibleWithHttpx;

  # Unwrapped ansible-core for reference.
  unwrapped = python3Packages.ansible-core;

  shellHook = "";
  env = { };

  meta = {
    description = "ansible-core with httpx for API-driven collections";
  };
}
