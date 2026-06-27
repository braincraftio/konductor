---
name: pulumi
description: Konductor Pulumi IaC workflows. Use when working in infrastructure/pulumi/, editing Pulumi Python programs, running pulumi preview/up/destroy, managing stacks, or debugging Pulumi provider/plugin issues in the Konductor platform.
---

# Konductor Pulumi

Konductor's infrastructure is Pulumi (Python) under `infrastructure/pulumi/`. The
Python environment is built by Nix (`src/packages/languages.nix` →
`python.withPackages`), not pip. Pulumi's language plugin and provider SDKs are
nix-managed; do not `pip install` into the venv.

## Environment facts

- `PULUMI_PYTHON_CMD` points at the nix `python.withPackages` interpreter. The
  `pulumi` CLI is a `symlinkJoin` wrapper that sets this (see
  `src/packages/pulumi.nix`). Never invoke a bare `pulumi` from outside the
  devshell.
- Provider SDKs in the env: `pulumi`, `pulumi-random` (nixpkgs); `pulumi-kubernetes`,
  `pulumi-tls`, `pulumi-docker-build`, `pulumi-cloudflare` (PyPI wheels merged into
  the single `withPackages` call).
- `Pulumi.yaml` sets `typechecker: pyright`. `pyright` is in `pythonEnv/bin/`
  because the language plugin runs it as a subprocess. Do not remove it.
- Native extensions (grpcio, protobuf, bcrypt) are linked against nix store libs.
  If you hit a `.so` load error, it means the venv was populated by pip instead of
  Nix — rebuild via the devshell, do not LD_LIBRARY_PATH-patch.

## Workflow

1. Enter the konductor devshell (direnv handles this). Confirm `pulumi version`
   and `python -c "import pulumi"` both resolve to nix store paths.
2. Select the stack: `pulumi stack select <stack>`.
3. **Always `pulumi preview` before `pulumi up`.** Read the full diff. Konductor
   stacks touch KubeVirt VMs and Talos clusters — an unreviewed `up` can recreate
   a VM and change its UID (see the UID-conflict class of bugs in git history).
4. For destroys, confirm the stack and namespace explicitly; never `destroy` from
   ambiguous context.

## Common failures

- **"typechecker is pyright, but pyright is not installed"** — the pythonEnv lost
  `pyrightPkg`. Check `src/packages/pulumi.nix` `pythonDeps` still lists it.
- **Provider SDK import error** — a wheel hash drifted. Update the hash in
  `src/packages/pulumi.nix` `mkPulumiPypiPackage`, do not vendor the wheel.
- **State lock** — `pulumi cancel` only after confirming no other `up` is running.

## Conventions

- Provider SDKs from nixpkgs when available; PyPI wheels only when not in
  `nixos-25.11` python313Packages, and always content-addressed (`fetchurl` with
  exact URL + hash).
- Secrets come from open-sesame / Pulumi config, never inline. Do not read `.env`
  or `secrets/` to populate Pulumi config by hand.
