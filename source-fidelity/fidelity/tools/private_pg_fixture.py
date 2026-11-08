"""New one-use owned PG snapshot. Only metadata survives cleanup, never the dump."""
import hashlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

from verify import ROOT

AUTH = ROOT / "run/PRIVATE_PG_HTML_AUTHORIZATION_20261107.json"
USAGE = ROOT / "run/PRIVATE_PG_HTML_USAGE_20261107.json"
RESULT = ROOT / "run/PRIVATE_PG_HTML_RESULT_20261107.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ticks(pid):
    return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def approval():
    raw = AUTH.read_bytes()
    record = json.loads(raw)
    assert record["experiment_limit"] == 1
    assert record["allowed_actor"] == "original Rails HTML reference only"
    assert record["user_action"] == "ask_user selection: Allow one disposable experiment"
    assert record["status"] == "authorized_not_yet_consumed"
    return sha(raw)


def claim(output, path=USAGE, auth_sha=None):
    record = {"status": "claimed", "phase": "setup", "authorization_sha256": auth_sha or approval(),
              "runner_pid": os.getpid(), "runner_start_ticks": ticks(os.getpid()), "output": str(output.resolve()),
              "claimed_at": time.time(), "rails_invocations": 0, "old_approval_reused": False}
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    return record


def update_usage(record):
    current = json.loads(USAGE.read_text())
    assert current["runner_pid"] == os.getpid() and current["runner_start_ticks"] == ticks(os.getpid())
    with USAGE.open("r+") as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        stream.seek(0)
        json.dump(record, stream, indent=2)
        stream.write("\n")
        stream.truncate()
        stream.flush()
        os.fsync(stream.fileno())


class PrivatePG:
    def __init__(self, base, output, authorization_sha256):
        self.base = base.resolve()
        self.output = output.resolve()
        self.data = self.base / "pg-data"
        self.dump = self.base / "snapshot.dump"
        self.socket = None
        self.server = None
        self.server_ticks = None
        self.env = os.environ.copy()
        for key in ("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGPASSWORD", "PGPASSFILE", "DATABASE_URL"):
            self.env.pop(key, None)
        self.record = {"authorization_sha256": authorization_sha256, "commands": [], "shared_pg_writes": False,
                       "cleanup_verified": False}

    def command(self, name, argv, env, *, input=None, timeout=180):
        completed = subprocess.run(argv, env=env, input=input, text=True, capture_output=True, timeout=timeout)
        # Diagnostic streams may contain production row context. Keep them ONLY
        # inside the 0700 temporary work tree, deleted with the raw snapshot.
        (self.base / (name + ".private.log")).write_text(completed.stdout + completed.stderr)
        self.record["commands"].append({"name": name, "returncode": completed.returncode,
                                         "stderr_sha256": sha(completed.stderr.encode())})
        if completed.returncode:
            raise RuntimeError(f"private fixture {name} failed ({completed.returncode}); diagnostic digest recorded")
        return completed.stdout.strip()

    def shared_proof(self, name):
        query = """SELECT current_database(),inet_server_port(),current_setting('default_transaction_read_only'),
          (SELECT count(*) FROM stylesheet_cache),
          (SELECT md5(coalesce(string_agg(row_to_json(s)::text, '' ORDER BY name), '')) FROM site_settings s),
          (SELECT md5(coalesce(string_agg(row_to_json(s)::text, '' ORDER BY id), '')) FROM stylesheet_cache s)"""
        proof = self.command(name, ["psql", "-XAt", "--no-password", "-c", query], self.source_env)
        assert proof.startswith("discourse_development|5499|on|")
        return proof

    def owned(self):
        assert self.server and self.server.poll() is None, "owned private postmaster not live"
        pid = self.server.pid
        assert ticks(pid) == self.server_ticks, "private postmaster PID reused"
        assert str(self.data).encode() in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        assert int((self.data / "postmaster.pid").read_text().splitlines()[0]) == pid
        assert Path(f"/proc/{pid}/exe").resolve() == Path(shutil.which("postgres")).resolve()

    def __enter__(self):
        self.base.mkdir(mode=0o700, parents=True, exist_ok=False)
        try:
            self.source_env = self.env | {"PGHOST": "127.0.0.1", "PGPORT": "5499", "PGUSER": "discourse",
                "PGDATABASE": "discourse_development", "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=120000"}
            self.record["shared_before"] = self.shared_proof("shared-before")
            self.command("snapshot", ["pg_dump", "--format=custom", "--no-owner", "--no-acl", "--no-password",
                "--host=127.0.0.1", "--port=5499", "--username=discourse", "--dbname=discourse_development",
                "--file", str(self.dump)], self.source_env, timeout=300)
            self.dump.chmod(0o600)
            self.record["snapshot_bytes"] = self.dump.stat().st_size
            self.command("initdb", ["initdb", "-D", str(self.data), "-U", "fixture_owner", "--encoding=UTF8", "--no-locale",
                "--auth-local=trust", "--auth-host=reject"], self.env)
            self.socket = Path(tempfile.mkdtemp(prefix="f25pg-"))
            self.socket.chmod(0o700)
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                self.port = reservation.getsockname()[1]
            assert self.port not in (5499, 6399)
            log = (self.base / "postmaster.private.log").open("wb")
            self.server = subprocess.Popen(["postgres", "-D", str(self.data), "-k", str(self.socket), "-p", str(self.port),
                "-c", "listen_addresses=", "-c", "unix_socket_permissions=0700", "-c", "max_connections=24",
                "-c", "shared_buffers=32MB", "-c", "fsync=off", "-c", "full_page_writes=off",
                "-c", "archive_mode=off", "-c", "shared_preload_libraries=", "-c", "synchronous_commit=off"],
                env=self.env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
            log.close()
            self.server_ticks = ticks(self.server.pid)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if self.server.poll() is not None:
                    raise RuntimeError("private postmaster exited during setup")
                pidfile = self.data / "postmaster.pid"
                if pidfile.exists() and len(lines := pidfile.read_text().splitlines()) >= 8 and lines[7].strip() == "ready":
                    break
                time.sleep(0.05)
            else:
                raise TimeoutError("private postmaster readiness timeout")
            self.owned()
            self.admin_env = self.env | {"PGHOST": str(self.socket), "PGPORT": str(self.port), "PGUSER": "fixture_owner",
                "PGDATABASE": "postgres", "PGOPTIONS": "-c statement_timeout=120000"}
            self.command("create-private-database", ["createdb", "--no-password", "discourse_development"], self.admin_env)
            self.admin_env["PGDATABASE"] = "discourse_development"
            self.command("restore-private", ["pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--no-password",
                "--dbname=discourse_development", str(self.dump)], self.admin_env, timeout=300)
            role_sql = """CREATE ROLE discourse LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
              REVOKE CREATE ON SCHEMA public FROM PUBLIC;
              GRANT CONNECT ON DATABASE discourse_development TO discourse;
              GRANT USAGE ON SCHEMA public TO discourse;
              GRANT SELECT ON ALL TABLES IN SCHEMA public TO discourse;
              GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO discourse;
              GRANT INSERT, DELETE ON public.stylesheet_cache TO discourse;
              GRANT INSERT, UPDATE ON public.site_settings TO discourse;
              GRANT pg_read_all_settings TO discourse;
              ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;
              CREATE POLICY fixture_settings_read ON public.site_settings FOR SELECT TO discourse USING (true);
              CREATE POLICY fixture_wizard_insert ON public.site_settings FOR INSERT TO discourse
                WITH CHECK (name = 'bypass_wizard_check' AND value = 't' AND data_type = 5);
              CREATE POLICY fixture_wizard_update ON public.site_settings FOR UPDATE TO discourse
                USING (name = 'bypass_wizard_check')
                WITH CHECK (name = 'bypass_wizard_check' AND value = 't' AND data_type = 5);
            """
            self.command("restrict-private-rails-role", ["psql", "-X", "-v", "ON_ERROR_STOP=1"], self.admin_env, input=role_sql)
            self.app_env = self.admin_env | {"PGUSER": "discourse", "PGOPTIONS": "-c statement_timeout=15000 -c lock_timeout=5000"}
            live = self.command("verify-private-identity", ["psql", "-XAt", "-c",
                "SELECT current_database(),current_user,current_setting('data_directory'),current_setting('port'),current_setting('listen_addresses'),current_setting('default_transaction_read_only')"], self.app_env)
            assert live == f"discourse_development|discourse|{self.data}|{self.port}||off"
            permissions = self.command("verify-private-restrictions", ["psql", "-XAt", "-c", """SELECT
              (SELECT NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole FROM pg_roles WHERE rolname=current_user),
              has_table_privilege('users','INSERT'), has_table_privilege('stylesheet_cache','INSERT'),
              (SELECT relrowsecurity FROM pg_class WHERE oid='public.site_settings'::regclass)"""], self.app_env)
            assert permissions == "t|f|t|t"
            self.record["private_restrictions_verified"] = True
            self.owned()
            sock = self.socket / f".s.PGSQL.{self.port}"
            assert sock.is_socket() and sock.stat().st_uid == os.geteuid()
            self.manifest = self.base / "private-pg-manifest.json"
            manifest = {"schema": 1, "kind": "owned_original_html_pg_20261107", "authorization_path": str(AUTH),
                "authorization_sha256": self.record["authorization_sha256"], "output": str(self.output),
                "runner_pid": os.getpid(), "runner_start_ticks": ticks(os.getpid()), "owner_uid": os.geteuid(),
                "postgres_pid": self.server.pid, "postgres_start_ticks": self.server_ticks,
                "postgres_executable": str(Path(f"/proc/{self.server.pid}/exe").resolve()),
                "data_directory": str(self.data), "socket_directory": str(self.socket), "port": self.port,
                "database": "discourse_development", "user": "discourse",
                "socket_identity": [sock.stat().st_dev, sock.stat().st_ino]}
            self.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
            self.manifest.chmod(0o600)
            self.record.update(status="ready", postgres_pid=self.server.pid, private_port=self.port,
                               owned_server_verified=True, tcp_listener_enabled=False)
            return self
        except BaseException:
            self.cleanup()
            raise

    def cleanup(self):
        errors = []
        postmaster_stopped = self.server is None
        if self.server:
            try:
                if self.server.poll() is None:
                    # Even a startup failure may lack a complete pidfile. Popen
                    # parenthood, start ticks and exact command/datadir prove it.
                    assert ticks(self.server.pid) == self.server_ticks
                    assert str(self.data).encode() in Path(f"/proc/{self.server.pid}/cmdline").read_bytes().split(b"\0")
                    self.server.terminate()
                    try:
                        self.server.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        assert ticks(self.server.pid) == self.server_ticks
                        self.server.kill()
                        self.server.wait(timeout=10)
                else:
                    self.server.wait()
                self.record["owned_postmaster_reaped"] = True
                postmaster_stopped = True
            except BaseException as error:
                errors.append(type(error).__name__ + ": owned PG shutdown failed")
        if hasattr(self, "source_env"):
            try:
                self.record["shared_after"] = self.shared_proof("shared-after")
                assert self.record["shared_after"] == self.record["shared_before"]
                self.record["shared_critical_rows_unchanged"] = True
            except BaseException as error:
                errors.append(type(error).__name__ + ": shared readonly post-check failed")
        if postmaster_stopped:
            if self.socket and self.socket.exists():
                shutil.rmtree(self.socket)
            if self.base.exists():
                shutil.rmtree(self.base)
        self.record.update(cleanup_verified=not errors, cleanup_errors=errors,
            raw_snapshot_removed=not self.dump.exists(), data_removed=not self.data.exists(),
            socket_removed=self.socket is None or not self.socket.exists(), sensitive_work_removed=not self.base.exists())
        if errors:
            raise RuntimeError("; ".join(errors))

    def __exit__(self, *_):
        self.cleanup()
