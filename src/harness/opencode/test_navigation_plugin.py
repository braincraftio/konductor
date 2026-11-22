"""Run the production TUI plugin acceptance suite inside an isolated tmux server."""

import argparse
import shlex
import subprocess
import tempfile
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--opencode", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(
        prefix="navigation-acceptance-", dir="/tmp/opencode"
    ) as directory:
        root = Path(directory)
        tmux = ["tmux", "-S", str(root / "tmux.sock"), "-f", "/dev/null"]

        def call(*arguments: str) -> str:
            return subprocess.run(
                [*tmux, *arguments], check=True, capture_output=True, text=True, timeout=5
            ).stdout.strip()

        try:
            call("new-session", "-d", "-s", "navigation", "-x", "120", "-y", "40", "sleep 300")
            output, status = root / "output", root / "status"
            command = (
                'KONDUCTOR_TEST_TMUX="$TMUX" KONDUCTOR_TEST_PANE="$TMUX_PANE" '
                + "OPENCODE_SOURCE="
                + shlex.quote(str(args.opencode.resolve()))
                + " KONDUCTOR_NAVIGATION_HELPER="
                + shlex.quote(str(args.helper.resolve()))
                + " bun test --timeout 30000 "
                + shlex.quote(str(Path(__file__).with_name("navigation.test.ts").resolve()))
                + " > "
                + shlex.quote(str(output))
                + " 2>&1; echo $? > "
                + shlex.quote(str(status))
                + "; exec sleep 300"
            )
            call("split-window", "-h", "-c", str(args.opencode.resolve() / "packages/tui"), command)
            deadline = time.monotonic() + 65
            while not status.exists():
                if time.monotonic() > deadline:
                    print(output.read_text())
                    raise TimeoutError("plugin acceptance exceeded 65 seconds")
                time.sleep(0.1)
            print(output.read_text())
            return int(status.read_text())
        finally:
            subprocess.run([*tmux, "kill-server"], capture_output=True, timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
