"""Parse the /.konductor build fingerprint and /etc/os-release.

The /.konductor file is a TOML file baked into every QCOW2 image at build
time by the build pipeline (_build:qcow2:vm:provenance task in BUILD.md).
It contains git, nix, and build metadata used to derive certificate identity.

/etc/os-release provides NixOS version information for additional provenance.
"""

from __future__ import annotations

import socket
from dataclasses import dataclass, field
from pathlib import Path

from pki import config


@dataclass(frozen=True)
class Fingerprint:
    """Build fingerprint from /.konductor TOML.

    All fields are optional -- when the file doesn't exist or a field
    is missing, the value is None and consumers use defaults.
    """

    git_commit: str | None = None
    git_branch: str | None = None
    git_remote: str | None = None
    git_dirty: int | None = None
    nix_drv: str | None = None
    nix_hash: str | None = None
    nix_version: str | None = None
    flake_lock_sha256: str | None = None
    build_date: str | None = None
    build_host: str | None = None
    build_user: str | None = None
    qemu: str | None = None
    strict: bool = False
    oci_image: str | None = None
    oci_tags: list[str] = field(default_factory=list)
    image_sha256: str | None = None
    image_size: str | None = None

    @classmethod
    def load(cls, path: Path | None = None) -> Fingerprint:
        """Load fingerprint from TOML file. Returns empty on failure."""
        path = Path(path) if path else config.FINGERPRINT_PATH

        if not path.exists():
            return cls()

        try:
            import tomllib
        except ModuleNotFoundError:
            # Python < 3.11 fallback
            try:
                import tomli as tomllib  # type: ignore[no-redef]
            except ModuleNotFoundError:
                return cls._parse_fallback(path)

        try:
            with open(path, "rb") as f:
                data = tomllib.load(f)
        except Exception:
            return cls()

        # /.konductor has a [konductor] section
        section = data.get("konductor", data)

        return cls(
            git_commit=section.get("git_commit"),
            git_branch=section.get("git_branch"),
            git_remote=section.get("git_remote"),
            git_dirty=section.get("git_dirty"),
            nix_drv=section.get("nix_drv"),
            nix_hash=section.get("nix_hash"),
            nix_version=section.get("nix_version"),
            flake_lock_sha256=section.get("flake_lock_sha256"),
            build_date=section.get("build_date"),
            build_host=section.get("build_host"),
            build_user=section.get("build_user"),
            qemu=section.get("qemu"),
            strict=bool(section.get("strict", False)),
            oci_image=section.get("oci_image"),
            oci_tags=section.get("oci_tags", []),
            image_sha256=section.get("image_sha256"),
            image_size=section.get("image_size"),
        )

    @classmethod
    def _parse_fallback(cls, path: Path) -> Fingerprint:
        """Minimal TOML parser for when tomllib/tomli are unavailable.

        Only handles the simple key = "value" and key = number patterns
        present in /.konductor. Does NOT handle nested tables, arrays, etc.
        """
        values: dict[str, str] = {}
        try:
            for line in path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("["):
                    continue
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip('"')
                values[key] = val
        except Exception:
            return cls()

        dirty = values.get("git_dirty")
        return cls(
            git_commit=values.get("git_commit"),
            git_branch=values.get("git_branch"),
            git_remote=values.get("git_remote"),
            git_dirty=int(dirty) if dirty and dirty.isdigit() else None,
            nix_drv=values.get("nix_drv"),
            nix_hash=values.get("nix_hash"),
            nix_version=values.get("nix_version"),
            flake_lock_sha256=values.get("flake_lock_sha256"),
            build_date=values.get("build_date"),
            build_host=values.get("build_host"),
            build_user=values.get("build_user"),
            qemu=values.get("qemu"),
            strict=values.get("strict", "false").lower() == "true",
            oci_image=values.get("oci_image"),
            image_sha256=values.get("image_sha256"),
            image_size=values.get("image_size"),
        )


@dataclass(frozen=True)
class OSRelease:
    """NixOS version information from /etc/os-release."""

    version_id: str | None = None      # e.g. "25.11"
    version_codename: str | None = None  # e.g. "xantusia"
    version: str | None = None          # e.g. "25.11 (Xantusia)"
    name: str | None = None             # e.g. "NixOS"
    hostname: str | None = None         # runtime hostname

    @classmethod
    def load(cls, path: Path | None = None) -> OSRelease:
        """Load from /etc/os-release. Returns defaults on failure."""
        path = Path(path) if path else config.OS_RELEASE_PATH
        values: dict[str, str] = {}

        try:
            for line in path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                values[key.strip()] = val.strip().strip('"')
        except Exception:
            pass

        try:
            hostname = socket.gethostname()
        except Exception:
            hostname = None

        return cls(
            version_id=values.get("VERSION_ID"),
            version_codename=values.get("VERSION_CODENAME"),
            version=values.get("VERSION"),
            name=values.get("NAME") or values.get("VENDOR_NAME"),
            hostname=hostname,
        )

    @property
    def display(self) -> str:
        """Human-readable NixOS version string."""
        parts = []
        if self.name:
            parts.append(self.name)
        if self.version_id:
            parts.append(self.version_id)
        if self.version_codename:
            parts.append(f"({self.version_codename})")
        return " ".join(parts) if parts else "NixOS"
