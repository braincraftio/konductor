---
name: qcow2
description: Konductor QCOW2 image build and NixOS VM provisioning. Use when working in src/qcow2/, building the konductor disk image, debugging cloud-init/systemd user services/skel provisioning, or the open-sesame integration in the Konductor VM.
---

# Konductor QCOW2

`src/qcow2/default.nix` builds the konductor NixOS disk image (native nixpkgs
image building, no nixos-generators). It boots as a KubeVirt VMI and serves
built-in users (kc2, kc2admin, runner) plus cloud-init dynamic users.

## Provisioning model (the hard-won parts)

- **Built-in users** get home dirs provisioned at build time by home-manager.
- **Cloud-init dynamic users** do NOT get `useradd --copy-skel` on NixOS. `/etc/skel`
  must contain REAL files, not nix-store symlinks — symlinks copy as-is and leave
  home pointing at read-only store paths (EACCES on first `~/.config` write).
  `skelPackage` is a `runCommand` derivation writing real files via `passAsFile`.
- Home-dir population + chown happens in **cloud-init runcmd at boot**, not
  profile.d (profile.d runs at interactive login — too late for systemd user
  services that start at boot via linger).
- systemd user services need their `ReadWritePaths` target dirs to exist BEFORE
  the mount namespace is set up; a oneshot `*-dirs` service (no ProtectHome) runs
  `mkdir -p` first. `ExecStartPre` can't do this — it runs inside the namespace.

## Common failures

- **EACCES on ~/.config/~/.cache** — skel shipped symlinks instead of real files.
- **exit 226/NAMESPACE** — `ReadWritePaths` dir missing at namespace setup.
- **exit 203/EXEC** — wrong binary name (nix package name ≠ deb name; e.g.
  `daemon-launcher` not `launcher`).
- **"Service has no ExecStart="** — setting only `wantedBy` generates an empty
  unit shadowing the package's. Either provide a full definition or rely on the
  package unit + `wantedBy` enablement, not a partial override.
- **UID conflict on deploy** — build host user leaked into the sealed image.
  Build cloud-init must use the declarative NixOS user (kc2admin), never create
  `$USER`.

## Workflow

1. Build via the runme pipeline (`docs/ci/build.md`), not ad-hoc nix-build.
2. After image changes touching users/services, verify on a live VM: dirs
   oneshot runs first → namespace setup succeeds → services active.
3. Image cleaning (`_img-clean`) cannot undo declarative NixOS state — fix the
   source (cloud-init / nix config), not the sealed image.

## Conventions

- Delegate service definitions to upstream packages where possible; NixOS only
  enables (`wantedBy`).
- TLS trust: prefer mounted hypervisor CA (`/mnt/pki/ca.crt`) when present.
