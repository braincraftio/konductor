"""Rewrite version blocks managed by src/apps/sync-versions.nix.

The spec (JSON, rendered by Nix from src/lib/versions.nix) lists, per file:
  blocks: marker-delimited regions whose content is replaced
          (style "html": <!-- sync-versions:begin NAME --> ... end NAME -->,
           style "hash": # sync-versions:begin NAME ... # sync-versions:end NAME)
  lines:  single lines identified by a prefix that must occur exactly once

Every begin and end marker must occur exactly once, in order, and a managed
file may not contain markers the spec does not name. --check compares
without writing and exits 1 with a unified diff when a file is out of date.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import TypedDict

MARKERS = {
    "html": ("<!-- sync-versions:begin {} -->", "<!-- sync-versions:end {} -->"),
    "hash": ("# sync-versions:begin {}", "# sync-versions:end {}"),
}
BEGIN_TOKEN = "sync-versions:begin "


class Block(TypedDict):
    name: str
    style: str
    content: str


class Line(TypedDict):
    prefix: str
    content: str


class FileSpec(TypedDict):
    path: str
    blocks: list[Block]
    lines: list[Line]


class SyncError(Exception):
    """A managed file does not have the structure the spec requires."""


def only_index(lines: list[str], marker: str, path: str) -> int:
    hits = [i for i, text in enumerate(lines) if text.strip() == marker]
    if len(hits) != 1:
        raise SyncError(f"{path}: expected exactly one '{marker}', found {len(hits)}")
    return hits[0]


def apply_block(lines: list[str], block: Block, path: str) -> list[str]:
    if block["style"] not in MARKERS:
        valid = ", ".join(sorted(MARKERS))
        raise SyncError(f"{path}: unknown marker style '{block['style']}' (valid: {valid})")
    begin_template, end_template = MARKERS[block["style"]]
    begin = only_index(lines, begin_template.format(block["name"]), path)
    end = only_index(lines, end_template.format(block["name"]), path)
    if end <= begin:
        raise SyncError(f"{path}: end marker for '{block['name']}' precedes its begin marker")
    return lines[: begin + 1] + block["content"].splitlines() + lines[end:]


def apply_line(lines: list[str], line: Line, path: str) -> list[str]:
    hits = [i for i, text in enumerate(lines) if text.startswith(line["prefix"])]
    if len(hits) != 1:
        raise SyncError(
            f"{path}: expected exactly one line starting '{line['prefix']}', found {len(hits)}"
        )
    updated = list(lines)
    updated[hits[0]] = line["content"]
    return updated


def render(text: str, spec: FileSpec) -> str:
    path = spec["path"]
    lines = text.split("\n")
    declared = sum(1 for text_line in lines if BEGIN_TOKEN in text_line)
    if declared != len(spec["blocks"]):
        raise SyncError(
            f"{path}: {declared} begin markers present, {len(spec['blocks'])} managed by the spec"
        )
    for block in spec["blocks"]:
        lines = apply_block(lines, block, path)
    for line in spec["lines"]:
        lines = apply_line(lines, line, path)
    return "\n".join(lines)


def write_atomic(target: Path, content: str) -> None:
    mode = target.stat().st_mode
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--spec", required=True, type=Path, help="JSON spec rendered by Nix")
    parser.add_argument("--root", required=True, type=Path, help="repository root")
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    args = parser.parse_args()

    specs: list[FileSpec] = json.loads(args.spec.read_text(encoding="utf-8"))
    stale = []
    try:
        for spec in specs:
            target = args.root / spec["path"]
            current = target.read_text(encoding="utf-8")
            updated = render(current, spec)
            if updated == current:
                continue
            stale.append(spec["path"])
            if args.check:
                sys.stdout.writelines(
                    difflib.unified_diff(
                        current.splitlines(keepends=True),
                        updated.splitlines(keepends=True),
                        fromfile=f"a/{spec['path']}",
                        tofile=f"b/{spec['path']}",
                    )
                )
            else:
                write_atomic(target, updated)
                print(f"updated {spec['path']}")
    except (SyncError, FileNotFoundError) as error:
        print(f"sync-versions: {error}", file=sys.stderr)
        return 2

    if args.check and stale:
        print(
            f"sync-versions: {len(stale)} file(s) out of date; run: nix run .#sync-versions",
            file=sys.stderr,
        )
        return 1
    if not stale:
        print(f"sync-versions: {len(specs)} file(s) current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
