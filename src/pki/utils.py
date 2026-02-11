"""File I/O utilities for security-critical PKI operations.

All file writes are atomic (write-to-temp then rename) to prevent
partial writes from leaving the PKI in an inconsistent state.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path


def ensure_dir(path: Path, mode: int = 0o755) -> None:
    """Create directory with specified permissions, including parents."""
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, mode)


def atomic_write(path: Path, data: bytes, mode: int = 0o644) -> None:
    """Write bytes atomically using rename on the same filesystem.

    Writes to a temp file in the same directory, sets permissions,
    fsyncs, then renames. If anything fails, the temp file is cleaned up
    and the original file (if any) is untouched.
    """
    path = Path(path)
    ensure_dir(path.parent)

    tmp_fd: int | None = None
    tmp_path: str | None = None

    try:
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=path.parent,
            prefix=f".{path.name}.",
        )
        os.write(tmp_fd, data)
        os.fchmod(tmp_fd, mode)
        os.fsync(tmp_fd)
        os.close(tmp_fd)
        tmp_fd = None
        os.rename(tmp_path, path)
        tmp_path = None  # rename succeeded, no cleanup needed
    finally:
        if tmp_fd is not None:
            os.close(tmp_fd)
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def emit(symbol: str, message: str, *, file: object = None) -> None:
    """Print a status line with a symbol prefix.

    Symbols:
        checkmark  = success
        cross      = error
        arrow      = action in progress
        dot        = informational
    """
    out = file or sys.stdout
    print(f"  {symbol} {message}", file=out)  # type: ignore[arg-type]


def info(message: str) -> None:
    emit("\u00b7", message)


def ok(message: str) -> None:
    emit("\u2713", message)


def err(message: str) -> None:
    emit("\u2717", message, file=sys.stderr)


def action(message: str) -> None:
    emit("\u2192", message)
