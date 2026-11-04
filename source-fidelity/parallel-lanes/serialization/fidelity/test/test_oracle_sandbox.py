from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from oracle_sandbox import ValkeySandbox


def redis_command(host: str, port: int, *args: str) -> bytes:
    with socket.create_connection((host, port), timeout=1) as client:
        parts = [a.encode() for a in args]
        client.sendall(b"*%d\r\n" % len(parts) + b"".join(b"$%d\r\n%s\r\n" % (len(p), p) for p in parts))
        return client.recv(1024)


class ValkeySandboxTest(unittest.TestCase):
    def test_private_fixture_real_write_and_cleanup_evidence(self):
        with tempfile.TemporaryDirectory() as root:
            build = Path(root) / "build"
            sandbox = ValkeySandbox(build)
            with sandbox:
                env = sandbox.environment
                host, port = env["FIDELITY_VALKEY_HOST"], int(env["FIDELITY_VALKEY_PORT"])
                self.assertEqual((host, port), ("127.0.0.1", sandbox.port))
                self.assertNotIn(port, (5499, 6399))
                self.assertEqual(redis_command(host, port, "SET", "fidelity:test", "written"), b"+OK\r\n")
                self.assertEqual(redis_command(host, port, "GET", "fidelity:test"), b"$7\r\nwritten\r\n")
                info = redis_command(host, port, "INFO", "server")
                self.assertIn(f"process_id:{sandbox.process.pid}".encode(), info)
                proof = json.loads(Path(env["FIDELITY_VALKEY_EVIDENCE"]).read_text())
                self.assertEqual(proof["status"], "ready")
                self.assertEqual(proof["pid"], int(env["FIDELITY_VALKEY_PID"]))
                self.assertEqual(proof["info_process_id"], sandbox.process.pid)
                self.assertEqual(proof["runtime_config"]["bind"], ["127.0.0.1"])
                self.assertEqual(proof["runtime_config"]["port"], port)
                self.assertEqual(proof["runtime_config"]["unixsocket"], "")
                self.assertEqual(proof["runtime_config"]["appendonly"], "no")
                self.assertTrue(proof["ready_ping"])
                self.assertEqual(proof["config"]["bind"], ["127.0.0.1"])
                self.assertTrue(proof["config"]["loopback_only"])
                self.assertEqual(proof["config"]["port"], port)
                self.assertEqual(proof["config"]["save"], "")
                self.assertEqual(proof["config"]["appendonly"], "no")
                self.assertEqual(env["DISCOURSE_REDIS_HOST"], host)
                self.assertEqual(env["DISCOURSE_REDIS_PORT"], str(port))
                self.assertEqual(env["DISCOURSE_MESSAGE_BUS_REDIS_HOST"], host)
                self.assertEqual(env["DISCOURSE_MESSAGE_BUS_REDIS_PORT"], str(port))
                self.assertEqual(env["REDIS_URL"], f"redis://{host}:{port}/0")
                self.assertEqual(env["FIDELITY_PG_CONNECTION_LOG"], str(build / "pg-connections.jsonl"))
            self.assertIsNotNone(sandbox.process.poll())
            stopped = json.loads(sandbox.evidence_path.read_text())
            self.assertEqual(stopped["status"], "stopped")
            self.assertEqual(stopped["cleanup"], "child_exited")
            self.assertTrue(sandbox.cleanup_complete)
            self.assertEqual(stopped["config"]["bind"], ["127.0.0.1"])

    def test_exception_path_cleans_only_child(self):
        with tempfile.TemporaryDirectory() as root:
            sandbox = ValkeySandbox(Path(root) / "build")
            with self.assertRaisesRegex(RuntimeError, "test failure"):
                with sandbox:
                    pid = sandbox.process.pid
                    raise RuntimeError("test failure")
            self.assertEqual(sandbox.process.pid, pid)
            self.assertIsNotNone(sandbox.process.poll())
            self.assertEqual(json.loads(sandbox.evidence_path.read_text())["cleanup"], "child_exited")


if __name__ == "__main__":
    unittest.main()
