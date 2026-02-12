"""Parse /.konductor and self-discover provenance from the source tree.

Two provenance sources, one truth:

1. /.konductor -- TOML file baked by the build pipeline. Contains git,
   nix, and build metadata written at image build time.

2. /opt/konductor/src -- the source tree shipped inside every VM,
   including .git history. Self-discoverable at runtime.

When /.konductor exists, it MUST parse cleanly and its git_commit MUST
match the source tree. Any mismatch is a build integrity failure and
the tool refuses to generate certificates.

When /.konductor does not exist (first boot, pre-provenance), certs are
explicitly marked ephemeral. "unknown" is never acceptable output.

/etc/os-release provides NixOS version information.
"""

from __future__ import annotations

import hashlib
import socket
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from pki import config


class FingerprintError(Exception):
    """Raised when /.konductor exists but cannot be parsed or validated."""


@dataclass(frozen=True)
class Fingerprint:
    """Build fingerprint from /.konductor TOML.

    All fields are optional only in the ephemeral (pre-provenance) case
    when /.konductor does not exist. When the file exists, critical
    fields (git_commit, nix_drv) must be present and valid.
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
    # Build host hardware identity (from /sys/devices/virtual/dmi/id/)
    build_hw_vendor: str | None = None
    build_hw_product: str | None = None
    build_hw_serial: str | None = None
    strict: bool = False
    oci_image: str | None = None
    oci_tags: list[str] = field(default_factory=list)
    image_sha256: str | None = None
    image_size: str | None = None

    @property
    def is_ephemeral(self) -> bool:
        """True when no provenance data is available (pre-provenance boot)."""
        return self.git_commit is None and self.nix_drv is None

    @classmethod
    def load(cls, path: Path | None = None) -> Fingerprint:
        """Load fingerprint from TOML file.

        Returns empty Fingerprint (ephemeral) when file does not exist.
        Raises FingerprintError when file exists but cannot be parsed.
        """
        path = Path(path) if path else config.FINGERPRINT_PATH

        if not path.exists():
            return cls()

        # Parse TOML -- errors are fatal, not silent
        try:
            import tomllib
        except ModuleNotFoundError:
            try:
                import tomli as tomllib  # type: ignore[no-redef]
            except ModuleNotFoundError:
                # No TOML library: use line parser (still strict)
                return cls._parse_strict(path)

        try:
            with open(path, "rb") as f:
                data = tomllib.load(f)
        except Exception as exc:
            # TOML parse failure is a build integrity error
            # Show the actual error so the operator can fix the source
            raise FingerprintError(
                f"Failed to parse {path}: {exc}\n"
                f"  This indicates a malformed /.konductor file.\n"
                f"  The build pipeline wrote invalid TOML.\n"
                f"  Refusing to generate certificates with corrupt provenance."
            ) from exc

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
            build_hw_vendor=section.get("build_hw_vendor"),
            build_hw_product=section.get("build_hw_product"),
            build_hw_serial=section.get("build_hw_serial"),
            strict=bool(section.get("strict", False)),
            oci_image=section.get("oci_image"),
            oci_tags=section.get("oci_tags", []),
            image_sha256=section.get("image_sha256"),
            image_size=section.get("image_size"),
        )

    @classmethod
    def _parse_strict(cls, path: Path) -> Fingerprint:
        """Line-by-line TOML parser for when tomllib is unavailable.

        Handles simple key = "value" and key = number patterns.
        Raises FingerprintError on any parse failure.
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
        except Exception as exc:
            raise FingerprintError(
                f"Failed to read {path}: {exc}"
            ) from exc

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
            build_hw_vendor=values.get("build_hw_vendor"),
            build_hw_product=values.get("build_hw_product"),
            build_hw_serial=values.get("build_hw_serial"),
            strict=values.get("strict", "false").lower() == "true",
            oci_image=values.get("oci_image"),
            image_sha256=values.get("image_sha256"),
            image_size=values.get("image_size"),
        )

    @classmethod
    def discover(cls, source_tree: Path | None = None) -> Fingerprint:
        """Self-discover provenance from the source tree and running system.

        Gathers what can be determined from:
        - /opt/konductor/src/.git (git commit, branch, remote, dirty)
        - /opt/konductor/src/flake.lock (sha256)

        Only populates fields that are directly comparable to /.konductor.
        Does NOT discover nix_drv (/.konductor stores the flake output
        hash from the build host; /run/current-system is the system
        derivation hash — different semantic, comparing them is wrong).

        Returns a Fingerprint with only discoverable fields populated.
        Fields that require build context (build_date, build_host,
        build_user, oci_image, oci_tags) are left None.
        """
        src = source_tree or config.SOURCE_TREE
        git_dir = src / ".git"

        git_commit = None
        git_branch = None
        git_remote = None
        git_dirty = None

        if git_dir.exists():
            git_commit = _run_strict(
                ["git", "-C", str(src), "rev-parse", "HEAD"],
                "git rev-parse HEAD",
            )
            branch = _run_strict(
                ["git", "-C", str(src), "rev-parse", "--abbrev-ref", "HEAD"],
                "git rev-parse --abbrev-ref HEAD",
            )
            git_branch = branch if branch != "HEAD" else None
            git_remote = _run_strict(
                ["git", "-C", str(src), "remote", "get-url", "origin"],
                "git remote get-url origin",
            )
            porcelain = _run_strict(
                ["git", "-C", str(src), "status", "--porcelain"],
                "git status --porcelain",
            )
            git_dirty = len(porcelain.splitlines()) if porcelain else 0

        # flake.lock sha256
        flake_lock = src / "flake.lock"
        flake_lock_sha256 = None
        if flake_lock.exists():
            flake_lock_sha256 = hashlib.sha256(
                flake_lock.read_bytes()
            ).hexdigest()

        return cls(
            git_commit=git_commit,
            git_branch=git_branch,
            git_remote=git_remote,
            git_dirty=git_dirty,
            flake_lock_sha256=flake_lock_sha256,
        )

    def validate_against(self, discovered: Fingerprint) -> list[str]:
        """Validate baked provenance against self-discovered values.

        Returns list of validation errors. Empty list = valid.
        Only validates fields that are present in both baked and discovered.
        """
        errors: list[str] = []

        if self.git_commit and discovered.git_commit:
            if self.git_commit != discovered.git_commit:
                errors.append(
                    f"git_commit mismatch: "
                    f"baked={self.git_commit[:12]} "
                    f"discovered={discovered.git_commit[:12]}"
                )

        if self.flake_lock_sha256 and discovered.flake_lock_sha256:
            if self.flake_lock_sha256 != discovered.flake_lock_sha256:
                errors.append(
                    f"flake_lock_sha256 mismatch: "
                    f"baked={self.flake_lock_sha256[:16]}... "
                    f"discovered={discovered.flake_lock_sha256[:16]}..."
                )

        return errors


def _run_strict(cmd: list[str], description: str) -> str:
    """Run a command and return stripped stdout. Raises on failure.

    Every discovery command is expected to succeed when its
    preconditions are met (e.g. .git exists). Failures indicate
    a broken source tree, not an expected condition.
    """
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except Exception as exc:
        raise FingerprintError(
            f"Discovery command failed: {description}\n"
            f"  Command: {' '.join(cmd)}\n"
            f"  Error: {exc}"
        ) from exc

    if result.returncode != 0:
        raise FingerprintError(
            f"Discovery command failed: {description}\n"
            f"  Command: {' '.join(cmd)}\n"
            f"  Exit code: {result.returncode}\n"
            f"  Stderr: {result.stderr.strip()}"
        )

    return result.stdout.strip()


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
