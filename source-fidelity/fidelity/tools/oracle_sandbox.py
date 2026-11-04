"""Disposable, task-owned loopback Valkey fixture for the unchanged Rails oracle.

    with ValkeySandbox(build_dir) as sandbox:
        env = {**os.environ, **sandbox.environment}
        run_oracle(env=env)

The short-lived Popen child is bound only to 127.0.0.1 on a dynamically
selected port; persistence and service registration are disabled. Cleanup only
signals that child and leaves evidence in the caller-owned build directory.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import subprocess
import time
from typing import Optional


class ValkeySandbox:
    def __init__(self, build_dir: os.PathLike[str] | str, *, evidence_dir: os.PathLike[str] | str | None = None,
                 executable: str = "valkey-server", startup_timeout: float = 5.0):
        self.build_dir = Path(build_dir).resolve()
        self.evidence_dir = Path(evidence_dir).resolve() if evidence_dir else self.build_dir
        self.executable = executable
        self.startup_timeout = startup_timeout
        self.process: Optional[subprocess.Popen[bytes]] = None
        self.host = "127.0.0.1"
        self.port: Optional[int] = None
        self.evidence_path = self.evidence_dir / "valkey-sandbox.json"
        self._started_at: Optional[float] = None
        self._cleanup_status = "not_started"

    def __enter__(self) -> "ValkeySandbox":
        self.build_dir.mkdir(parents=True, exist_ok=True)
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        # Ask the kernel for an unused ephemeral port, then close the reservation
        # before starting Valkey. PID + INFO process_id validation detects races.
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
            reservation.bind((self.host, 0))
            self.port = reservation.getsockname()[1]
        if self.port in (5499, 6399):
            raise RuntimeError("kernel unexpectedly selected a protected task/shared port")
        command = [self.executable, "--port", str(self.port), "--bind", self.host,
                   "--save", "", "--appendonly", "no", "--dir", str(self.build_dir),
                   "--daemonize", "no", "--protected-mode", "yes"]
        self.stdout_path = self.build_dir / "valkey.stdout"
        self.stderr_path = self.build_dir / "valkey.stderr"
        self._stdout = self.stdout_path.open("wb")
        self._stderr = self.stderr_path.open("wb")
        try:
            self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                            stdout=self._stdout, stderr=self._stderr,
                                            close_fds=True, start_new_session=True)
            self._started_at = time.time()
            self._write_evidence("starting")
            deadline = time.monotonic() + self.startup_timeout
            while time.monotonic() < deadline:
                if self.process.poll() is not None:
                    raise RuntimeError(f"Valkey exited before readiness ({self.process.returncode}); see {self.stderr_path}")
                try:
                    if self._ping():
                        pid = self._info_process_id()
                        if pid != self.process.pid:
                            raise RuntimeError(f"loopback port owner PID {pid} is not sandbox child {self.process.pid}")
                        runtime_bind = self._config_value("bind").split()
                        runtime_port = int(self._config_value("port"))
                        if runtime_bind != [self.host] or runtime_port != self.port:
                            raise RuntimeError(f"unexpected Valkey listeners: bind={runtime_bind}, port={runtime_port}")
                        if self._config_value("unixsocket") != "":
                            raise RuntimeError("Valkey unexpectedly enabled a Unix-domain listener")
                        if self._config_value("save") != "":
                            raise RuntimeError("Valkey unexpectedly enabled snapshot persistence")
                        if self._config_value("appendonly").lower() != "no" or self._config_value("protected-mode").lower() != "yes":
                            raise RuntimeError("Valkey runtime persistence/protected-mode config does not match sandbox")
                        self._was_ready = True
                        self._write_evidence("ready", ready_ping=True, info_process_id=pid,
                                             runtime_config={"bind": runtime_bind, "port": runtime_port,
                                                             "unixsocket": "", "appendonly": "no",
                                                             "protected_mode": "yes"})
                        return self
                except (OSError, EOFError, ValueError):
                    pass
                time.sleep(0.025)
            raise TimeoutError("Valkey loopback endpoint did not answer PING/INFO before startup timeout")
        except BaseException:
            self.close()
            raise

    @property
    def cleanup_complete(self) -> bool:
        """True only after the owned child exited and stopped evidence is durable."""
        if not self.process or self.process.poll() is None or not self.evidence_path.is_file():
            return False
        try:
            proof = json.loads(self.evidence_path.read_text())
            return proof.get("status") == "stopped" and proof.get("cleanup") == "child_exited" and proof.get("pid") == self.process.pid
        except (OSError, json.JSONDecodeError):
            return False

    @property
    def environment(self) -> dict[str, str]:
        if not self.process or self.port is None or self.process.poll() is not None:
            raise RuntimeError("Valkey sandbox is not running")
        host, port = self.host, str(self.port)
        url = f"redis://{host}:{port}/0"
        return {"FIDELITY_VALKEY_HOST": host,
                "FIDELITY_VALKEY_PORT": port,
                "FIDELITY_VALKEY_PID": str(self.process.pid),
                "FIDELITY_VALKEY_EVIDENCE": str(self.evidence_path),
                "FIDELITY_VALKEY_WRITE_LOG": str(self.evidence_dir / "valkey-writes.jsonl"),
                "FIDELITY_PG_CONNECTION_LOG": str(self.evidence_dir / "pg-connections.jsonl"),
                "REDIS_URL": url,
                "DISCOURSE_REDIS_HOST": host,
                "DISCOURSE_REDIS_PORT": port,
                "DISCOURSE_MESSAGE_BUS_REDIS_HOST": host,
                "DISCOURSE_MESSAGE_BUS_REDIS_PORT": port}

    def _command(self, *args: str) -> bytes:
        assert self.port is not None
        with socket.create_connection((self.host, self.port), timeout=0.25) as client:
            encoded = [a.encode() for a in args]
            client.sendall(b"*%d\r\n" % len(encoded) + b"".join(b"$%d\r\n%s\r\n" % (len(a), a) for a in encoded))
            return client.recv(65536)

    def _ping(self) -> bool:
        return self._command("PING") == b"+PONG\r\n"

    def _info_process_id(self) -> int:
        response = self._command("INFO", "server")
        if not response.startswith(b"$"):
            raise ValueError(f"unexpected INFO response: {response[:80]!r}")
        body = response.split(b"\r\n", 1)[1]
        fields = dict(line.split(b":", 1) for line in body.splitlines() if b":" in line)
        return int(fields[b"process_id"])

    def _config_value(self, key: str) -> str:
        response = self._command("CONFIG", "GET", key)
        fields = response.split(b"\r\n")
        if not fields or fields[0] != b"*2" or len(fields) < 6 or fields[2].decode() != key:
            raise ValueError(f"unexpected CONFIG GET {key} response: {response[:120]!r}")
        return fields[4].decode()

    def _write_evidence(self, status: str, **extra: object) -> None:
        payload = {"status": status, "pid": self.process.pid if self.process else None,
                   "host": self.host, "port": self.port,
                   "config": {"bind": [self.host], "port": self.port, "loopback_only": True,
                              "save": "", "appendonly": "no", "protected_mode": True,
                              "dir": str(self.build_dir)},
                   "started_at": self._started_at, "cleanup": self._cleanup_status, **extra}
        self.evidence_path.write_text(json.dumps(payload, indent=2) + "\n")

    def close(self) -> None:
        process = self.process
        if process is not None:
            if process.poll() is None:
                # This handle is exclusively the Popen child created above.
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            self._cleanup_status = "child_exited" if process.poll() is not None else "cleanup_failed"
        else:
            self._cleanup_status = "not_started"
        for stream_name in ("_stdout", "_stderr"):
            stream = getattr(self, stream_name, None)
            if stream and not stream.closed:
                stream.close()
        self._write_evidence("stopped", ready_ping=getattr(self, "_was_ready", False))

    def __exit__(self, exc_type, exc, traceback) -> bool:
        self.close()
        return False


__all__ = ["ValkeySandbox"]
