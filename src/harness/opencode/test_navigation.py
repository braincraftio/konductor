import importlib.util
import json
import os
import pty
import queue
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

SOURCE = Path(__file__).with_name("navigation.py")
SPEC = importlib.util.spec_from_file_location("navigation", SOURCE)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"cannot load {SOURCE}")
navigation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(navigation)


class ControlTest(unittest.TestCase):
    def exchange(self, reply: bytes) -> bool:
        with tempfile.TemporaryDirectory(prefix="navigation-control-", dir="/tmp/opencode") as root:
            endpoint = str(Path(root) / "control.sock")
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(endpoint)
                server.listen(1)
                server.settimeout(2)

                def respond() -> None:
                    stream, _ = server.accept()
                    with stream:
                        stream.settimeout(2)
                        request = bytearray()
                        while len(request) < 4:
                            request.extend(stream.recv(4 - len(request)))
                        size = struct.unpack("!I", request)[0]
                        payload = bytearray()
                        while len(payload) < size:
                            chunk = stream.recv(size - len(payload))
                            if not chunk:
                                raise RuntimeError("incomplete test request")
                            payload.extend(chunk)
                        for byte in reply:
                            stream.sendall(bytes([byte]))

                with ThreadPoolExecutor(max_workers=1) as executor:
                    worker = executor.submit(respond)
                    try:
                        result: bool = navigation.control(
                            {
                                "OPENCODE_PTY_CONTROL_SOCKET": endpoint,
                                "OPENCODE_PTY_CONTROL_TOKEN": "test",
                                "OPENCODE_PTY_ID": "1",
                            },
                            {"op": "claim_navigation", "pid": os.getpid()},
                        )
                        return result
                    finally:
                        worker.result(timeout=3)

    def test_fragmented_reply(self) -> None:
        payload = b'{"type":"ok"}'
        self.assertTrue(self.exchange(struct.pack("!I", len(payload)) + payload))

    def test_non_object_reply(self) -> None:
        for payload in (b"null", b"[]", b"1"):
            with self.subTest(payload=payload):
                with self.assertRaisesRegex(ValueError, "response must be an object"):
                    self.exchange(struct.pack("!I", len(payload)) + payload)

    def test_truncated_reply(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "complete response"):
            self.exchange(struct.pack("!I", 8) + b"{")

    def test_oversized_reply(self) -> None:
        with self.assertRaisesRegex(ValueError, "response size"):
            self.exchange(struct.pack("!I", 65537))

    def test_controller_rejection(self) -> None:
        payload = b'{"type":"error","message":"wrong session"}'
        with self.assertRaisesRegex(RuntimeError, "wrong session"):
            self.exchange(struct.pack("!I", len(payload)) + payload)


class NavigationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="k9-nav-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        binary = shutil.which("tmux")
        if binary is None:
            self.fail("tmux is not on PATH")
        self.binary = str(self.root / "tmux")
        Path(self.binary).write_text(
            "#!/bin/sh\nexec "
            + shlex.quote(binary)
            + " -S "
            + shlex.quote(str(self.root / "tmux.sock"))
            + ' -f /dev/null "$@"\n'
        )
        Path(self.binary).chmod(0o700)
        self.addCleanup(
            lambda: subprocess.run([self.binary, "kill-server"], capture_output=True, timeout=3)
        )
        self.call("new-session", "-d", "-s", "navigation", "-x", "100", "-y", "30", "sleep 3600")
        self.first = self.call("display-message", "-p", "#{pane_id}")

    def call(self, *args: str) -> str:
        result: str = navigation.tmux(self.binary, *args)
        return result

    def register(self, target: str, pid: int, socket: Path) -> None:
        subprocess.run(
            [
                sys.executable,
                str(SOURCE),
                "--tmux",
                self.binary,
                "register",
                target,
                str(pid),
                str(socket),
            ],
            check=True,
            capture_output=True,
            timeout=3,
        )

    def test_edges_never_wrap_and_inactive_panes_do_not_move(self) -> None:
        second = self.call("split-window", "-h", "-P", "-F", "#{pane_id}", "sleep 3600")
        self.assertFalse(navigation.move(self.binary, second, "right"))
        self.assertEqual(self.call("display-message", "-p", "#{pane_id}"), second)
        self.assertFalse(navigation.move(self.binary, self.first, "right"))
        self.assertTrue(navigation.move(self.binary, second, "left"))
        self.assertEqual(self.call("display-message", "-p", "#{pane_id}"), self.first)
        self.assertFalse(navigation.move(self.binary, self.first, "left"))
        self.assertFalse(navigation.move(self.binary, self.first, "up"))
        self.assertFalse(navigation.move(self.binary, self.first, "down"))
        self.assertTrue(navigation.move(self.binary, self.first, "right"))
        self.assertEqual(self.call("display-message", "-p", "#{pane_id}"), second)

    def attach(self, session: str, marker: str) -> tuple[str, int]:
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        self.client_master = master
        tty = os.ttyname(slave)
        process = subprocess.Popen(
            [self.binary, "attach-session", "-t", session],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=dict(
                os.environ,
                TERM="xterm-256color",
                TMUX="",
                OPENCODE_PTY_CONTROL_SOCKET=marker,
                OPENCODE_PTY_CONTROL_TOKEN="client-token",
                OPENCODE_PTY_ID="42",
            ),
            start_new_session=True,
        )

        def cleanup() -> None:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=3)

        self.addCleanup(cleanup)
        deadline = time.monotonic() + 3
        while tty not in self.call("list-clients", "-F", "#{client_tty}").splitlines():
            self.assertIsNone(process.poll(), "tmux client exited before attachment")
            self.assertLess(time.monotonic(), deadline, "tmux client did not attach")
            time.sleep(0.01)
        return tty, process.pid

    def test_client_credentials_are_specific_to_attached_client(self) -> None:
        first, first_pid = self.attach("navigation", "/first-parent")
        second, second_pid = self.attach("navigation", "/second-parent")
        for tty, pid, endpoint in (
            (first, first_pid, "/first-parent"),
            (second, second_pid, "/second-parent"),
        ):
            actual, environment = navigation.client_environment(self.binary, self.first, tty)
            self.assertEqual(actual, pid)
            self.assertEqual(
                environment,
                {
                    "OPENCODE_PTY_CONTROL_SOCKET": endpoint,
                    "OPENCODE_PTY_CONTROL_TOKEN": "client-token",
                    "OPENCODE_PTY_ID": "42",
                },
            )

    def test_client_from_another_session_is_rejected(self) -> None:
        first, _ = self.attach("navigation", "/first-parent")
        other = self.call(
            "new-session", "-d", "-s", "other", "-P", "-F", "#{pane_id}", "sleep 3600"
        )
        self.attach("other", "/other-parent")
        with self.assertRaisesRegex(RuntimeError, "client changed"):
            navigation.client_environment(self.binary, other, first)

    @unittest.skipUnless(os.environ.get("KONDUCTOR_TEST_TMUX_CONFIG"), "requires built tmux config")
    def test_generated_bindings_claim_client_move_locally_and_propagate_edge(self) -> None:
        config = Path(os.environ["KONDUCTOR_TEST_TMUX_CONFIG"]).read_text()
        bindings = [
            line
            for line in config.splitlines()
            if "konductor-pane-navigation" in line
            and line.lstrip().startswith(("bind-key ", "set-hook "))
        ]
        self.assertEqual(len(bindings), 7)
        generated = self.root / "navigation.conf"
        generated.write_text("\n".join(bindings) + "\n")
        self.call("source-file", str(generated))
        second = self.call("split-window", "-h", "-P", "-F", "#{pane_id}", "sleep 3600")
        endpoint = str(self.root / "controller.sock")
        received: queue.Queue[Any] = queue.Queue()
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(endpoint)
            server.listen(8)
            server.settimeout(5)

            def respond() -> None:
                # Attachment and session-change hooks claim; crossing the edge claims again,
                # then sends the directional notification on its own connection.
                for _ in range(4):
                    stream, _ = server.accept()
                    with stream:
                        stream.settimeout(2)

                        def read(size: int, stream: socket.socket = stream) -> bytearray:
                            data = bytearray()
                            while len(data) < size:
                                chunk = stream.recv(size - len(data))
                                if not chunk:
                                    raise RuntimeError("incomplete controller request")
                                data.extend(chunk)
                            return data

                        size = struct.unpack("!I", read(4))[0]
                        received.put(json.loads(read(size)))
                        payload = b'{"type":"ok"}'
                        stream.sendall(struct.pack("!I", len(payload)) + payload)

            with ThreadPoolExecutor(max_workers=1) as executor:
                worker = executor.submit(respond)
                _, pid = self.attach("navigation", endpoint)
                self.assertEqual(
                    received.get(timeout=4),
                    {
                        "token": "client-token",
                        "request": {"op": "claim_navigation", "pid": pid, "id": 42},
                    },
                )
                self.assertEqual(
                    received.get(timeout=4)["request"],
                    {"op": "claim_navigation", "pid": pid, "id": 42},
                )
                os.write(self.client_master, b"\x08")
                deadline = time.monotonic() + 3
                while self.call("display-message", "-p", "#{pane_id}") != self.first:
                    self.assertLess(time.monotonic(), deadline, "Ctrl+H did not move left")
                    time.sleep(0.01)
                self.assertTrue(received.empty(), "local movement reached outer controller")
                os.write(self.client_master, b"\x08")
                self.assertEqual(
                    received.get(timeout=4)["request"],
                    {"op": "claim_navigation", "pid": pid, "id": 42},
                )
                self.assertEqual(
                    received.get(timeout=4)["request"],
                    {"op": "notify_controller", "message": "pane.navigate.left", "id": 42},
                )
                self.assertEqual(self.call("display-message", "-p", "#{pane_id}"), self.first)
                self.assertNotEqual(self.first, second)
                worker.result(timeout=3)

    def test_claim_tracks_foreground_lifetime_and_enabled_state(self) -> None:
        endpoint = self.root / "claim.sock"
        identity = self.root / "pid"
        enabled = self.root / "enabled"
        enabled.write_text("true")
        responder = self.root / "responder.py"
        responder.write_text(
            "import json, os, socket\n"
            "from pathlib import Path\n"
            f"Path({str(identity)!r}).write_text(str(os.getpid()))\n"
            f"enabled = Path({str(enabled)!r})\n"
            "with socket.socket(socket.AF_UNIX) as server:\n"
            f" server.bind({str(endpoint)!r})\n"
            " server.listen(8)\n"
            " while True:\n"
            "  stream, _ = server.accept()\n"
            "  with stream:\n"
            "   try:\n"
            "    stream.sendall((json.dumps({'pid': os.getpid(), "
            "'enabled': enabled.read_text() == 'true' and os.getpgrp() == os.tcgetpgrp(0), "
            "'tty': os.ttyname(0)}) + '\\n').encode())\n"
            "   except BrokenPipeError:\n"
            "    pass\n"
        )
        target = self.call(
            "split-window",
            "-h",
            "-P",
            "-F",
            "#{pane_id}",
            shlex.join([sys.executable, str(responder)]) + "; exec sleep 3600",
        )
        deadline = time.monotonic() + 3
        while not endpoint.exists():
            self.assertLess(time.monotonic(), deadline, "claimant socket did not open")
            time.sleep(0.01)
        pid = int(identity.read_text())
        self.register(target, pid, endpoint)
        self.assertTrue(navigation.admitted(self.binary, target))
        enabled.write_text("false")
        self.assertFalse(navigation.admitted(self.binary, target))
        enabled.write_text("true")
        self.register(self.first, pid, endpoint)
        self.assertFalse(navigation.admitted(self.binary, self.first))
        os.kill(pid, signal.SIGSTOP)
        try:
            deadline = time.monotonic() + 3
            while (
                not subprocess.check_output(["ps", "-o", "stat=", "-p", str(pid)], text=True)
                .strip()
                .startswith("T")
            ):
                self.assertLess(time.monotonic(), deadline, "claimant did not stop")
                time.sleep(0.01)
            self.assertFalse(navigation.admitted(self.binary, target))
        finally:
            os.kill(pid, signal.SIGCONT)
        self.assertTrue(navigation.admitted(self.binary, target))
        with navigation.lifetime(pid) as alive:
            os.kill(pid, signal.SIGKILL)
            deadline = time.monotonic() + 3
            while alive():
                self.assertLess(time.monotonic(), deadline, "claimant did not exit")
                time.sleep(0.01)
        self.assertFalse(navigation.admitted(self.binary, target))


if __name__ == "__main__":
    unittest.main()
