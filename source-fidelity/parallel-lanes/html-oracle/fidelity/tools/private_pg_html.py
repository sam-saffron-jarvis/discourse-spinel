#!/usr/bin/env python3
"""One explicitly authorized Rails HTML experiment on an owned disposable PG copy.

The shared database is only read by pg_dump with forced read-only options. The
private server listens on a private Unix socket, never on TCP. Raw dump and
private server data are removed in finally; only diagnostic metadata survives.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path('/home/agent/work/discourse-spinel')
AUTH = ROOT / 'run/PRIVATE_PG_HTML_ORACLE_AUTHORIZATION.json'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def start_ticks(pid: int) -> str:
    # comm may contain spaces; fields after ')' start at stat field 3.
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]


def live_owned_process(pid: int, expected_ticks: str, proc_root: Path = Path('/proc')) -> bool:
    try:
        fields = (proc_root / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
    except FileNotFoundError:
        return False
    # A zombie cannot serve SQL, and a reused PID is not our old server.
    return fields[0] != 'Z' and fields[19] == expected_ticks


def checked(argv: list[str], *, env: dict[str, str], log: Path, timeout: int = 180) -> str:
    p = subprocess.run(argv, env=env, text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=timeout)
    # Keep command diagnostics private; the summary never embeds SQL/data.
    log.write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(f'{Path(argv[0]).name} failed ({p.returncode}); private log {log.name}')
    return p.stdout.strip()


class PrivatePG:
    def __init__(self, base: Path):
        self.base = base.resolve()
        self.data = self.base / 'pg-data'
        self.dump = self.base / 'snapshot.dump'
        self.socket = None
        self.record = {'authorized_scope': 'one original Rails HTML oracle experiment',
                       'authorization_path': str(AUTH), 'authorization_sha256': digest(AUTH),
                       'shared_pg_writes': False, 'cleanup_verified': False}
        self.pid = None
        self.ticks = None
        self.environment = os.environ.copy()
        for name in ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGPASSWORD']:
            self.environment.pop(name, None)

    def save(self):
        (self.base / 'private-pg-evidence.json').write_text(json.dumps(self.record, indent=2) + '\n')

    def owned(self):
        if not self.pid or start_ticks(self.pid) != self.ticks:
            raise RuntimeError('private PostgreSQL process identity no longer matches')
        cmd = Path(f'/proc/{self.pid}/cmdline').read_bytes().split(b'\0')
        if str(self.data).encode() not in cmd:
            raise RuntimeError('private PostgreSQL does not own the expected data directory')
        if int((self.data / 'postmaster.pid').read_text().splitlines()[0]) != self.pid:
            raise RuntimeError('private PostgreSQL pidfile mismatch')

    def __enter__(self):
        auth = json.loads(AUTH.read_text())
        if auth.get('selected_option') != 'Allow writable disposable copy' or not auth.get('one_experiment_not_blanket_permission'):
            raise RuntimeError('explicit bounded private-PG authorization missing')
        self.base.mkdir(parents=True, exist_ok=False, mode=0o700)
        os.chmod(self.base, 0o700)
        try:
            source_env = self.environment | {'PGHOST': '127.0.0.1', 'PGPORT': '5499',
                'PGUSER': 'discourse', 'PGDATABASE': 'discourse_development',
                'PGOPTIONS': '-c default_transaction_read_only=on -c statement_timeout=120000'}
            proof = checked(['psql', '-X', '-A', '-t', '-c',
                "SELECT current_database(),inet_server_port(),current_setting('default_transaction_read_only')"],
                env=source_env, log=self.base/'source-readonly.log')
            if proof != 'discourse_development|5499|on':
                raise RuntimeError('shared source is not the exact read-only task endpoint')
            self.record['shared_before'] = proof
            checked(['pg_dump', '--format=custom', '--no-owner', '--no-acl', '--no-password',
                     '--file', str(self.dump)], env=source_env, log=self.base/'snapshot.log', timeout=300)
            os.chmod(self.dump, 0o600)
            self.record['snapshot_bytes'] = self.dump.stat().st_size
            checked(['initdb', '-D', str(self.data), '-U', 'discourse', '--encoding=UTF8',
                     '--no-locale', '--auth-local=trust', '--auth-host=reject'],
                    env=self.environment, log=self.base/'initdb.log')
            self.socket = Path(tempfile.mkdtemp(prefix='rhpg-html-'))
            os.chmod(self.socket, 0o700)
            with socket.socket() as s:
                s.bind(('127.0.0.1', 0)); self.port = s.getsockname()[1]
            if self.port == 5499:
                raise RuntimeError('private PostgreSQL may not use shared port')
            options = (f"-k {self.socket} -p {self.port} -c listen_addresses='' "
                       '-c unix_socket_permissions=0700 -c max_connections=24 '
                       '-c shared_buffers=32MB -c fsync=off -c full_page_writes=off '
                       '-c synchronous_commit=off')
            checked(['pg_ctl', '-D', str(self.data), '-l', str(self.base/'postgres-private.log'),
                     '-o', options, '-w', 'start'], env=self.environment, log=self.base/'start.log')
            self.pid = int((self.data/'postmaster.pid').read_text().splitlines()[0])
            self.ticks = start_ticks(self.pid)
            self.owned()
            private_env = self.environment | {'PGHOST': str(self.socket), 'PGPORT': str(self.port),
                'PGUSER': 'discourse', 'PGDATABASE': 'postgres',
                'PGOPTIONS': '-c statement_timeout=120000'}
            checked(['createdb', 'discourse_development'], env=private_env, log=self.base/'createdb.log')
            private_env['PGDATABASE'] = 'discourse_development'
            checked(['pg_restore', '--no-owner', '--no-acl', '--exit-on-error',
                     '--dbname=discourse_development', str(self.dump)],
                    env=private_env, log=self.base/'restore.log', timeout=300)
            proof = checked(['psql', '-X', '-A', '-t', '-c',
                "SELECT current_database(),current_setting('data_directory'),current_setting('default_transaction_read_only')"],
                env=private_env, log=self.base/'private-target.log')
            if proof != f'discourse_development|{self.data}|off':
                raise RuntimeError('private writable PG identity check failed')
            self.owned()
            sock = self.socket / f'.s.PGSQL.{self.port}'
            if not sock.is_socket() or sock.stat().st_uid != os.geteuid():
                raise RuntimeError('private PostgreSQL socket ownership failed')
            manifest = {'schema': 1, 'kind': 'owned_disposable_html_oracle_pg',
                'authorization_path': str(AUTH), 'authorization_sha256': digest(AUTH),
                'runner_pid': os.getpid(), 'runner_start_ticks': start_ticks(os.getpid()),
                'owner_uid': os.geteuid(), 'postgres_pid': self.pid, 'postgres_start_ticks': self.ticks,
                'postgres_executable': os.readlink(f'/proc/{self.pid}/exe'),
                'data_directory': str(self.data), 'socket_directory': str(self.socket),
                'port': self.port, 'database': 'discourse_development', 'user': 'discourse',
                'tcp_listen_addresses': '', 'scope': 'one original Rails HTML trace; private copy writes only'}
            self.manifest = self.base / 'private-pg-manifest.json'
            self.manifest.write_text(json.dumps(manifest, indent=2)+'\n');os.chmod(self.manifest, 0o600)
            self.record.update(status='ready', manifest=manifest, shared_source_readonly=True)
            self.save()
            self.source_env = source_env
            self.private_env = private_env
            return self
        except BaseException:
            self.cleanup()
            raise

    def cleanup(self):
        errors = []
        if self.pid:
            try:
                self.owned()
                checked(['pg_ctl', '-D', str(self.data), '-m', 'fast', '-w', 'stop'],
                        env=self.environment, log=self.base/'stop.log')
                for _ in range(100):
                    if not live_owned_process(self.pid, self.ticks):
                        break
                    time.sleep(0.05)
                if live_owned_process(self.pid, self.ticks):
                    raise RuntimeError('private PostgreSQL process did not exit')
            except BaseException as e:
                errors.append(str(e))
        elif self.data.exists() and (self.data/'postmaster.pid').exists():
            errors.append('unexpected started instance without established ownership; data retained for safe recovery')
        if not errors:
            if self.data.exists(): shutil.rmtree(self.data)
            if self.dump.exists(): self.dump.unlink()
            if self.socket and self.socket.exists(): shutil.rmtree(self.socket)
        if hasattr(self, 'source_env'):
            try:
                after = checked(['psql', '-X', '-A', '-t', '-c',
                    "SELECT current_database(),inet_server_port(),current_setting('default_transaction_read_only')"],
                    env=self.source_env, log=self.base/'source-after.log')
                if after != 'discourse_development|5499|on': raise RuntimeError('shared read-only post-check failed')
                self.record['shared_after'] = after
            except BaseException as e: errors.append(str(e))
        self.record.update(cleanup_verified=not errors, cleanup_errors=errors,
                           raw_snapshot_removed=not self.dump.exists(), data_removed=not self.data.exists())
        if self.base.exists(): self.save()
        if errors: raise RuntimeError('; '.join(errors))

    def __exit__(self, *_):
        self.cleanup()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--asset-run',type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve()
    if out.exists():raise SystemExit('output must be new')
    usage = ROOT / 'run/PRIVATE_PG_HTML_ORACLE_USAGE.json'
    # One approval is not a renewable fixture license. The coordinator must
    # obtain new authorization before clearing/archiving this consumption record.
    try:
        fd = os.open(usage, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise SystemExit('the single approved private-PG experiment has already been claimed; no automatic rerun')
    with os.fdopen(fd, 'w') as handle:
        json.dump({'status':'claimed', 'authorization_sha256':digest(AUTH),
                   'runner_pid':os.getpid(), 'output':str(out)}, handle, indent=2)
    out.mkdir(parents=True,mode=0o700)
    result={'status':'in_progress','authorization_sha256':digest(AUTH)}
    try:
        with PrivatePG(out/'private-pg') as pg:
            env=os.environ.copy()
            env['FIDELITY_PRIVATE_PG_MANIFEST']=str(pg.manifest)
            command=[sys.executable,str(Path(__file__).with_name('trace_original_latest.py')),
                '--root',str(ROOT),'--output',str(out/'trace'),
                '--frontend-build-artifact',str(args.asset_run.resolve()),
                '--private-pg-manifest',str(pg.manifest)]
            p=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            (out/'runner.stdout').write_text(p.stdout);(out/'runner.stderr').write_text(p.stderr)
            result['trace_returncode']=p.returncode
            state=out/'trace/state.json'
            if state.exists():
                s=json.loads(state.read_text());summary=s.get('trace_summary',{})
                result.update(json_statuses=summary.get('page_json_statuses'),html=summary.get('html_phase'),
                              preloaders=summary.get('preloader_source_requirements'),
                              valkey_cleanup_verified=s.get('valkey_cleanup_verified'))
            result['status']='experiment_completed' if p.returncode==0 else 'experiment_failed'
    finally:
        evidence=out/'private-pg/private-pg-evidence.json'
        if evidence.exists():result['private_pg']=json.loads(evidence.read_text())
        (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        usage.write_text(json.dumps({'status':'consumed', 'authorization_sha256':digest(AUTH),
                                    'output':str(out), 'result':str(out/'result.json'),
                                    'no_automatic_rerun':True}, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='private_pg'},indent=2))
    return 0 if result['status']=='experiment_completed' else 1

if __name__=='__main__':
    raise SystemExit(main())
