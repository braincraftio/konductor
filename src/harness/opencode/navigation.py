"""Client-local tmux navigation and live foreground admission."""

import argparse
import contextlib
import json
import os
import re
import select
import socket
import struct
import subprocess
import sys
from collections.abc import Callable, Iterator, Mapping
from typing import Any

DIRECTIONS = {"left": "-L", "down": "-D", "up": "-U", "right": "-R", "previous": "-l"}
OPTION = "@konductor_navigation"


def control(environment: Mapping[str, str], operation: dict[str, Any]) -> bool:
    endpoint = environment.get("OPENCODE_PTY_CONTROL_SOCKET")
    token = environment.get("OPENCODE_PTY_CONTROL_TOKEN")
    raw_identifier = environment.get("OPENCODE_PTY_ID")
    if not endpoint or not token or not raw_identifier:
        return False
    identifier = int(raw_identifier)
    if identifier <= 0:
        raise ValueError("terminal ID must be positive")
    payload = json.dumps(
        {"token": token, "request": dict(operation, id=identifier)},
        separators=(",", ":"),
    ).encode()
    with socket.socket(socket.AF_UNIX) as stream:
        stream.settimeout(1)
        stream.connect(endpoint)
        stream.sendall(struct.pack("!I", len(payload)) + payload)

        def receive(size: int) -> bytearray:
            result = bytearray()
            while len(result) < size:
                chunk = stream.recv(size - len(result))
                if not chunk:
                    raise RuntimeError("terminal controller closed without a complete response")
                result.extend(chunk)
            return result

        size = struct.unpack("!I", receive(4))[0]
        if not 0 < size <= 65536:
            raise ValueError("invalid terminal controller response size")
        response = json.loads(receive(size))
    if not isinstance(response, dict):
        raise ValueError("terminal controller response must be an object")
    if response.get("type") != "ok":
        raise RuntimeError(response.get("message", "terminal controller rejected navigation"))
    return True


def client_environment(binary: str, target: str, client: str) -> tuple[int, dict[str, str]]:
    names = ("OPENCODE_PTY_CONTROL_SOCKET", "OPENCODE_PTY_CONTROL_TOKEN", "OPENCODE_PTY_ID")
    fields = ("#{client_tty}", "#{client_pid}", *("#{Ie:" + name + "}" for name in names))
    values = tmux(
        binary, "display-message", "-p", "-t", target, "-c", client, "\n".join(fields)
    ).split("\n")
    # display-message can choose another client when the requested client is in
    # another session. Never use that client's credentials for this boundary.
    if len(values) < 2 or values[0] != client:
        raise RuntimeError("tmux navigation client changed")
    environment = dict(zip(names, values[2:], strict=True))
    return int(values[1]), environment


def claim_client(binary: str, target: str, client: str) -> bool:
    pid, environment = client_environment(binary, target, client)
    return control(environment, {"op": "claim_navigation", "pid": pid})


def outer(binary: str, target: str, direction: str, client: str) -> bool:
    pid, environment = client_environment(binary, target, client)
    # Claim validation checks the client's POSIX session before a notification
    # can use inherited credentials to skip an intervening terminal layout.
    if not control(environment, {"op": "claim_navigation", "pid": pid}):
        return False
    return control(
        environment, {"op": "notify_controller", "message": "pane.navigate." + direction}
    )


def tmux(binary: str, *args: str) -> str:
    return subprocess.run(
        [binary, *args], check=True, capture_output=True, text=True, timeout=2
    ).stdout.strip()


def pane(value: str) -> str:
    if not re.fullmatch(r"%[0-9]+", value):
        raise ValueError("pane must be an absolute tmux pane ID")
    return value


@contextlib.contextmanager
def lifetime(pid: int) -> Iterator[Callable[[], bool]]:
    # Each branch is guarded directly by sys.platform so type checkers evaluate
    # only the current platform's select API.
    if sys.platform == "linux":
        descriptor = os.pidfd_open(pid)
        try:
            poll = select.poll()
            poll.register(descriptor, select.POLLIN)
            yield lambda: not poll.poll(0)
        finally:
            os.close(descriptor)
    elif sys.platform == "darwin":
        with select.kqueue() as queue:
            queue.control(
                [
                    select.kevent(
                        pid,
                        filter=select.KQ_FILTER_PROC,
                        flags=select.KQ_EV_ADD,
                        fflags=select.KQ_NOTE_EXIT,
                    )
                ],
                0,
                0,
            )
            yield lambda: not queue.control(None, 1, 0)
    else:
        raise RuntimeError("navigation admission requires Linux or macOS")


def admitted(binary: str, target: str) -> bool:
    record = tmux(binary, "display-message", "-p", "-t", target, "#{pane_tty}\n#{" + OPTION + "}")
    tty, _, encoded = record.partition("\n")
    if not encoded:
        return False
    claim = json.loads(encoded)
    if (
        not isinstance(claim, dict)
        or set(claim) != {"pid", "socket"}
        or type(claim["pid"]) is not int
        or claim["pid"] <= 0
        or not isinstance(claim["socket"], str)
    ):
        raise ValueError("invalid navigation admission record")
    try:
        with lifetime(claim["pid"]) as alive:
            with socket.socket(socket.AF_UNIX) as stream:
                stream.settimeout(0.25)
                stream.connect(claim["socket"])
                response = bytearray()
                while not response.endswith(b"\n"):
                    chunk = stream.recv(4096 - len(response))
                    if not chunk:
                        return False
                    response.extend(chunk)
                    if len(response) >= 4096:
                        raise ValueError("navigation admission response exceeds limit")
            value = json.loads(response)
            return bool(value == {"pid": claim["pid"], "enabled": True, "tty": tty}) and alive()
    except (ProcessLookupError, FileNotFoundError, ConnectionRefusedError, TimeoutError):
        return False


def move(binary: str, target: str, direction: str) -> bool:
    edges = {"left": "left", "right": "right", "up": "top", "down": "bottom"}
    edge = "0" if direction == "previous" else "#{pane_at_" + edges[direction] + "}"
    state = tmux(
        binary, "display-message", "-p", "-t", target, "#{pane_active} #{window_panes} " + edge
    )
    active, count, boundary = state.split()
    if active != "1" or int(count) < 2 or boundary == "1":
        return False
    tmux(binary, "select-pane", "-t", target, DIRECTIONS[direction])
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tmux", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("parent")
    claim = commands.add_parser("claim-client")
    claim.add_argument("pane", type=pane)
    claim.add_argument("client")
    foreground = commands.add_parser("foreground")
    foreground.add_argument("pid", type=int)
    check = commands.add_parser("admitted")
    check.add_argument("pane", type=pane)
    for name in ("move", "step"):
        navigate = commands.add_parser(name)
        navigate.add_argument("direction", choices=DIRECTIONS)
        navigate.add_argument("pane", type=pane)
        navigate.add_argument("--client")
    for name in ("register", "unregister"):
        registration = commands.add_parser(name)
        registration.add_argument("pane", type=pane)
        registration.add_argument("pid", type=int)
        registration.add_argument("socket")
    args = parser.parse_args()
    if args.command == "claim-client":
        claim_client(args.tmux, args.pane, args.client)
        return 0
    if args.command == "foreground":
        if args.pid <= 0:
            raise ValueError("foreground PID must be positive")
        # TIOCGPGRP must run inside the claimant's controlling session.
        if not os.isatty(0) or os.getpgid(args.pid) != os.tcgetpgrp(0):
            return 3
        print(os.ttyname(0))
        return 0
    if args.command == "parent":
        target = os.environ.get("TMUX_PANE")
        if not target or not os.isatty(0):
            return 3
        tty = tmux(args.tmux, "display-message", "-p", "-t", pane(target), "#{pane_tty}")
        if tty != os.ttyname(0):
            return 3
        print(target)
        return 0
    if args.command == "admitted":
        return 0 if admitted(args.tmux, args.pane) else 3
    if args.command in ("register", "unregister"):
        if args.pid <= 0 or not os.path.isabs(args.socket):
            raise ValueError("registration requires a positive PID and absolute socket path")
        record = json.dumps({"pid": args.pid, "socket": args.socket}, separators=(",", ":"))
        if args.command == "register":
            tmux(args.tmux, "set-option", "-p", "-t", args.pane, OPTION, record)
            return 0
        current = tmux(args.tmux, "display-message", "-p", "-t", args.pane, "#{" + OPTION + "}")
        if current == record:
            tmux(args.tmux, "set-option", "-pu", "-t", args.pane, OPTION)
        return 0
    moved = move(args.tmux, args.pane, args.direction)
    if not moved and args.client:
        active = tmux(args.tmux, "display-message", "-p", "-t", args.pane, "#{pane_active}")
        if active == "1":
            moved = outer(args.tmux, args.pane, args.direction, args.client)
    return 0 if moved or args.command == "step" else 3


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Konductor navigation: {error}", file=sys.stderr)
        sys.exit(1)
