#!/usr/bin/env python3
"""Run a source-pinned, isolated original Rails /latest trace.

All Rails files and mutable Rails tmp/log paths are materialized beneath the
explicit --output directory with `git archive`; --root is read-only. PostgreSQL
is guarded to task DB 5499 with transaction read-only forced on, and all Redis
clients must use the owned disposable Valkey fixture.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

HERE = Path(__file__).resolve().parents[1]
PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
MATERIALIZED_LOCK_FILES = (
    "app/models/topic.rb", "lib/topic_query.rb", "app/models/category.rb",
    "app/models/concerns/trashable.rb", "lib/archetype.rb", "lib/guardian.rb",
    "lib/guardian/topic_guardian.rb", "lib/guardian/category_guardian.rb",
    "app/models/site_setting.rb", "lib/site_setting_extension.rb",
    "lib/site_settings/yaml_loader.rb", "lib/site_settings/defaults_provider.rb",
    "lib/site_settings/db_provider.rb", "lib/site_settings/type_supervisor.rb",
    "app/models/theme_site_setting.rb", "lib/plugin/instance.rb",
    "lib/discourse_plugin_registry.rb", "lib/upcoming_changes.rb",
    "lib/application_layout_preloader.rb", "app/controllers/list_controller.rb",
    "lib/topic_list_responder.rb", "app/serializers/topic_list_serializer.rb",
    "app/serializers/topic_list_item_serializer.rb",
)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def expected_installed_pnpm_lock(pinned_lock: bytes) -> bytes:
    """Mirror PrecompiledBundle's byte-preserving `split(/^---\\n/).last`."""
    return re.split(br"^---\n", pinned_lock, flags=re.MULTILINE)[-1]


def copy_dependency_tree(source_modules: Path, copied_modules: Path, source_root: Path,
                         archive_root: Path) -> dict[str, int]:
    """Copy node_modules while proving every preserved symlink stays in the private archive.

    Symlink targets within node_modules resolve into the copied dependency tree;
    other targets must resolve inside the original checkout and have an archived
    counterpart (e.g. tracked frontend workspace packages). Absolute, dangling,
    or out-of-checkout links fail closed.
    """
    source_root = source_root.resolve(strict=True)
    source_modules = source_modules.resolve(strict=True)
    archive_root = archive_root.resolve(strict=True)
    if copied_modules.exists() or copied_modules.is_symlink():
        raise RuntimeError("private node_modules destination already exists")

    links: list[tuple[Path, Path, Path]] = []
    for link in source_modules.rglob("*"):
        if not link.is_symlink():
            continue
        raw_target = os.readlink(link)
        if os.path.isabs(raw_target):
            raise RuntimeError(f"absolute frontend dependency symlink rejected: {link.relative_to(source_modules)}")
        resolved = link.resolve(strict=True)
        try:
            relative_to_modules = resolved.relative_to(source_modules)
            if not resolved.exists():
                raise RuntimeError(f"broken frontend dependency symlink: {link}")
            target_in_archive = copied_modules / relative_to_modules
        except ValueError:
            try:
                relative_to_checkout = resolved.relative_to(source_root)
            except ValueError as error:
                raise RuntimeError(f"frontend dependency symlink escapes original checkout: {link}") from error
            target_in_archive = archive_root / relative_to_checkout
            if not target_in_archive.exists():
                raise RuntimeError(
                    f"frontend dependency symlink target is not materialized in private archive: "
                    f"{link.relative_to(source_modules)} -> {resolved}"
                )
        links.append((link, resolved, target_in_archive))

    shutil.copytree(source_modules, copied_modules, symlinks=True, copy_function=shutil.copy2)
    for original, _resolved, _target in links:
        private_link = copied_modules / original.relative_to(source_modules)
        if not private_link.is_symlink():
            raise RuntimeError(f"frontend dependency symlink was not preserved: {original.relative_to(source_modules)}")
        try:
            private_resolved = private_link.resolve(strict=True)
            private_resolved.relative_to(archive_root)
        except (FileNotFoundError, ValueError) as error:
            raise RuntimeError(
                f"copied frontend dependency symlink escapes or is unresolved: {original.relative_to(source_modules)}"
            ) from error
    return {"symlink_count": len(links), "symlink_targets_verified": len(links)}


def stage_frontend_node_modules(source_modules: Path, staged_modules: Path, source_root: Path,
                                 archive_root: Path) -> dict[str, int]:
    """Recreate the verified frontend dependency links into private archive packages.

    This mirrors Discourse's isolated build layout: each direct package link points
    at its resolved package, while generated `.embroider` state remains local.
    Targets are remapped into the private archive rather than source checkout.
    """
    source_root = source_root.resolve(strict=True)
    archive_root = archive_root.resolve(strict=True)
    source_modules = source_modules.resolve(strict=True)
    if staged_modules.exists() or staged_modules.is_symlink():
        raise RuntimeError("refusing to replace existing frontend node_modules")
    staged_modules.mkdir(parents=True)

    def private_target(entry: Path) -> Path:
        resolved = entry.resolve(strict=True)
        try:
            relative = resolved.relative_to(source_root)
        except ValueError as error:
            raise RuntimeError(f"frontend dependency escapes original checkout: {entry}") from error
        target = archive_root / relative
        if not target.exists():
            raise RuntimeError(f"resolved frontend dependency missing from private archive: {entry} -> {target}")
        return target

    links = 0
    for entry in sorted(source_modules.iterdir()):
        name = entry.name
        if name in {".bin", ".embroider"}:
            continue
        if name.startswith("@") and entry.is_dir():
            scope = staged_modules / name
            scope.mkdir()
            for scoped_entry in sorted(entry.iterdir()):
                target = private_target(scoped_entry)
                (scope / scoped_entry.name).symlink_to(target, target_is_directory=target.is_dir())
                links += 1
        else:
            target = private_target(entry)
            (staged_modules / name).symlink_to(target, target_is_directory=target.is_dir())
            links += 1

    source_bin = source_modules / ".bin"
    if source_bin.exists():
        shutil.copytree(source_bin, staged_modules / ".bin", symlinks=True)
    for link in staged_modules.rglob("*"):
        if link.is_symlink():
            resolved = link.resolve(strict=True)
            try:
                resolved.relative_to(archive_root)
            except ValueError as error:
                raise RuntimeError(f"staged frontend dependency escapes private archive: {link}") from error
    return {"symlink_count": links, "symlink_targets_verified": links}


def copy_workspace_dependency_trees(source_root: Path, archive_root: Path,
                                    excluded: set[str]) -> dict[str, dict[str, int]]:
    """Copy installed workspace-local node_modules needed by workspace imports."""
    source_root = source_root.resolve(strict=True)
    archive_root = archive_root.resolve(strict=True)
    discovered: list[Path] = []
    for top in ("frontend", "plugins", "themes", "docs"):
        base = source_root / top
        if not base.is_dir():
            continue
        for current, directories, _files in os.walk(base):
            if "node_modules" in directories:
                candidate = Path(current) / "node_modules"
                directories.remove("node_modules")
                relative = str(candidate.relative_to(source_root))
                if relative not in excluded:
                    discovered.append(candidate)
    result: dict[str, dict[str, int]] = {}
    for source_modules in sorted(discovered):
        relative = str(source_modules.relative_to(source_root))
        destination = archive_root / relative
        result[relative] = copy_dependency_tree(source_modules, destination, source_root, archive_root)
    return result


def run(argv: list[str], *, cwd: Path, env: dict[str, str], stdout: Path, stderr: Path,
        timeout_seconds: int | None = None) -> int:
    stdout.parent.mkdir(parents=True, exist_ok=True)
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=out, stderr=err,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        try:
            process.wait(timeout=timeout_seconds)
            return process.returncode
        except subprocess.TimeoutExpired:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            return 124
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise


def extract_pinned_source(repo: Path, target: Path) -> dict[str, str]:
    head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if head != PIN:
        raise RuntimeError(f"original checkout HEAD {head} != required pin {PIN}")
    status = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True)
    if status:
        raise RuntimeError("original checkout is not completely clean; refuse source ambiguity")
    proc = subprocess.Popen(["git", "-C", str(repo), "archive", "--format=tar", PIN], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    try:
        assert proc.stdout is not None
        with tarfile.open(fileobj=proc.stdout, mode="r|") as archive:
            archive.extractall(target, filter="data")
        stderr = proc.stderr.read() if proc.stderr else b""
        code = proc.wait()
        if code:
            raise RuntimeError(f"git archive failed ({code}): {stderr.decode(errors='replace')[:500]}")
    except BaseException:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        raise

    lock = json.loads((HERE / "SOURCE_LOCK.json").read_text())
    hashes: dict[str, str] = {}
    locked_by_path = {row["path"]: row["sha256"] for row in lock["files"]}
    for rel in MATERIALIZED_LOCK_FILES:
        expected = locked_by_path.get(rel)
        blob = subprocess.check_output(["git", "-C", str(repo), "show", f"{PIN}:{rel}"])
        copied = (target / rel).read_bytes()
        if (expected is not None and sha(blob) != expected) or copied != blob:
            raise RuntimeError(f"materialized original source mismatch: {rel}")
        hashes[rel] = sha(blob)
    return hashes


def frontend_build_source_hashes(discourse: Path) -> dict[str, str]:
    frontend = discourse / "frontend/discourse"
    source_files = [frontend / "package.json", frontend / "rolldown.config.mjs", frontend / "discourse.js"]
    source_files.extend(sorted(path for path in (frontend / "lib").rglob("*") if path.is_file()))
    return {str(path.relative_to(discourse)): sha(path.read_bytes())
            for path in source_files if path.is_file()}


def verified_frontend_dist_hashes(dist: Path) -> tuple[dict[str, str], int]:
    if not dist.is_dir():
        raise RuntimeError(f"frontend dist is absent: {dist}")
    outputs: dict[str, str] = {}
    total_bytes = 0
    for path in sorted(dist.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"frontend dist contains unexpected symlink: {path.relative_to(dist)}")
        if path.is_file():
            rel = str(path.relative_to(dist))
            outputs[rel] = sha(path.read_bytes())
            total_bytes += path.stat().st_size
    return outputs, total_bytes


def reuse_verified_frontend_build(artifact: Path, discourse: Path, output: Path) -> dict[str, object]:
    artifact = artifact.resolve(strict=True)
    allowed_root = HERE / "build"
    if artifact == allowed_root or allowed_root not in artifact.parents:
        raise RuntimeError("frontend build artifact must be an existing Fidelity-owned build directory")
    if output == artifact or output in artifact.parents or artifact in output.parents:
        raise RuntimeError("frontend build artifact and new trace output must be disjoint")
    state_path = artifact / "state.json"
    record_path = artifact / "frontend-asset-build.json"
    source_dist = artifact / "discourse/frontend/discourse/dist"
    if not state_path.is_file() or not record_path.is_file():
        raise RuntimeError("frontend artifact lacks trace state or asset-build provenance")
    state = json.loads(state_path.read_text())
    record = json.loads(record_path.read_text())
    if state.get("status") != "traced" or state.get("source_revision") != PIN or \
       state.get("source_checkout_not_modified") is not True:
        raise RuntimeError("frontend artifact is not from a completed unchanged pinned-source trace")
    if record.get("status") != "built" or record.get("inputs", {}).get("source_revision") != PIN:
        raise RuntimeError("frontend artifact does not record a successful build from the required pin")

    inputs = record["inputs"]
    source_lock = (discourse / "pnpm-lock.yaml").read_bytes()
    expected_lock = expected_installed_pnpm_lock(source_lock)
    if inputs.get("pinned_pnpm_lock_sha256") != sha(source_lock) or \
       inputs.get("installed_root_pnpm_lock_sha256") != sha(expected_lock):
        raise RuntimeError("frontend artifact lock provenance does not match the pinned checkout")
    if inputs.get("source_files_sha256") != frontend_build_source_hashes(discourse):
        raise RuntimeError("frontend artifact source/config hashes do not match the new archived source")

    expected_files = record.get("output_files_sha256")
    if not isinstance(expected_files, dict) or not expected_files:
        raise RuntimeError("frontend artifact has no per-file output hash inventory")
    observed_files, total_bytes = verified_frontend_dist_hashes(source_dist)
    if observed_files != expected_files:
        raise RuntimeError("frontend artifact output file/hash inventory differs from recorded provenance")
    manifest_rel = "manifest/manifest.json"
    if sha((source_dist / manifest_rel).read_bytes()) != record.get("manifest_sha256"):
        raise RuntimeError("frontend artifact manifest hash does not match its recorded provenance")
    if len(observed_files) != record.get("output_file_count") or total_bytes != record.get("output_bytes"):
        raise RuntimeError("frontend artifact output count/size does not match its recorded provenance")

    destination = discourse / "frontend/discourse/dist"
    if destination.exists():
        raise RuntimeError("refusing to overwrite private archived frontend dist")
    shutil.copytree(source_dist, destination, symlinks=False, copy_function=shutil.copy2)
    copied_files, copied_bytes = verified_frontend_dist_hashes(destination)
    if copied_files != expected_files or copied_bytes != total_bytes:
        raise RuntimeError("copied frontend assets failed recorded hash/size verification")
    return {
        "status": "reused_verified",
        "artifact_source": str(artifact),
        "source_revision": PIN,
        "manifest_sha256": record["manifest_sha256"],
        "output_file_count": len(copied_files),
        "output_bytes": copied_bytes,
        "output_files_sha256": copied_files,
        "inputs": inputs,
        "artifact_build_record_sha256": sha(record_path.read_bytes()),
    }


def run_frontend_asset_build(discourse: Path, output: Path, *, timeout_seconds: int = 600) -> dict[str, object]:
    frontend = discourse / "frontend/discourse"
    output_dist = frontend / "dist"
    manifest = output_dist / "manifest/manifest.json"
    if output_dist.exists():
        raise RuntimeError("refusing to overwrite pre-existing frontend dist output")
    strace = shutil.which("strace")
    node = shutil.which("node")
    env_command = shutil.which("env")
    if not strace or not node or not env_command:
        raise RuntimeError("frontend build requires existing strace, Node, and env binaries; no install attempted")

    home = output / "home"
    cache = output / "xdg-cache"
    tmp = output / "tmp"
    for directory in (home, cache, tmp):
        directory.mkdir(parents=True, exist_ok=True)
    build_env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "XDG_CACHE_HOME": str(cache),
        "TMPDIR": str(tmp),
        "CI": "1",
        "EMBER_ENV": "production",
        "NODE_ENV": "production",
    }

    source_hashes = frontend_build_source_hashes(discourse)
    package_file = frontend / "node_modules/rolldown/package.json"
    cli_file = frontend / "node_modules/rolldown/bin/cli.mjs"
    package_data = json.loads(package_file.read_text())
    inputs = {
        "source_revision": PIN,
        "source_files_sha256": source_hashes,
        "pinned_pnpm_lock_sha256": sha((discourse / "pnpm-lock.yaml").read_bytes()),
        "installed_root_pnpm_lock_sha256": sha((discourse / "node_modules/.pnpm/lock.yaml").read_bytes()),
        "rolldown_version": package_data.get("version"),
        "rolldown_package_json_sha256": sha(package_file.read_bytes()),
        "rolldown_cli_sha256": sha(cli_file.read_bytes()),
        "node_binary": node,
        "node_version": subprocess.check_output([node, "--version"], cwd=frontend, env=build_env,
                                                 text=True).strip(),
    }
    argv = [strace, "-f", "-qq", "-e",
            "inject=socket,socketpair,connect,sendto,sendmsg,recvfrom,recvmsg,bind,listen,accept,accept4:error=EPERM",
            "-o", str(output / "frontend-network-guard.strace"), env_command,
            "CI=1", "EMBER_ENV=production", "node", "node_modules/rolldown/bin/cli.mjs",
            "-c", "rolldown.config.mjs"]
    build_record: dict[str, object] = {
        "status": "in_progress",
        "working_directory": str(frontend),
        "argv": argv,
        "command_display": "env CI=1 EMBER_ENV=production node node_modules/rolldown/bin/cli.mjs -c rolldown.config.mjs",
        "network_guard": "strace injects EPERM for socket/connect/send/receive syscalls",
        "timeout_seconds": timeout_seconds,
        "inputs": inputs,
    }
    (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
    started = time.monotonic()
    rc = run(argv, cwd=frontend, env=build_env,
             stdout=output / "frontend-build.stdout", stderr=output / "frontend-build.stderr",
             timeout_seconds=timeout_seconds)
    build_record["elapsed_seconds"] = round(time.monotonic() - started, 3)
    build_record["returncode"] = rc
    network_trace = output / "frontend-network-guard.strace"
    network_events = network_trace.read_text(errors="replace").splitlines() if network_trace.exists() else []
    build_record["injected_network_syscall_count"] = sum("(INJECTED)" in line for line in network_events)
    build_record["kernel_denied_io_uring_count"] = sum(
        "io_uring_setup(" in line and "EPERM" in line for line in network_events
    )
    build_record["network_guard_log_sha256"] = sha(network_trace.read_bytes()) if network_trace.exists() else None
    if rc == 124:
        build_record["status"] = "timed_out"
        (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
        raise RuntimeError(f"original frontend build exceeded {timeout_seconds}s; process group terminated")
    if rc:
        build_record["status"] = "failed"
        (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
        raise RuntimeError(f"original frontend build failed with exit {rc}; see frontend-build.stdout/stderr")
    if not manifest.is_file():
        build_record["status"] = "missing_manifest"
        (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
        raise RuntimeError("original frontend build exited zero but omitted dist/manifest/manifest.json")

    outputs: dict[str, str] = {}
    total_bytes = 0
    for path in sorted(output_dist.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"frontend build emitted an unexpected symlink: {path.relative_to(output_dist)}")
        if path.is_file():
            rel = str(path.relative_to(output_dist))
            outputs[rel] = sha(path.read_bytes())
            total_bytes += path.stat().st_size
    build_record.update(status="built", manifest_sha256=sha(manifest.read_bytes()),
                        output_file_count=len(outputs), output_bytes=total_bytes,
                        output_files_sha256=outputs)
    (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
    return build_record


def make_env(root: Path, output: Path, discourse: Path, bundle_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "RAILS_ENV": "development",
        "RAILS_LOG_TO_STDOUT": "1",
        "BUNDLE_GEMFILE": str(discourse / "Gemfile"),
        "BUNDLE_PATH": str(bundle_path),
        "BUNDLE_FROZEN": "1",
        "FIDELITY_DISCOURSE_ROOT": str(discourse),
        "FIDELITY_ORACLE_GUARD": str(HERE / "tools/oracle_isolation.rb"),
        "FIDELITY_TRACE_OUTPUT": str(output),
        "FIDELITY_PG_CONNECTION_LOG": str(output / "pg-connections.jsonl"),
        "FIDELITY_VIPS_LOG": str(output / "vips-children.jsonl"),
        "FIDELITY_REJECTION_LOG": str(output / "endpoint-rejections.jsonl"),
        "FIDELITY_ORACLE_PHASE": "preflight",
        "PGHOST": "127.0.0.1", "PGPORT": "5499", "PGUSER": "discourse",
        "PGDATABASE": "discourse_development", "DATABASE_URL":
            "postgres://discourse@127.0.0.1:5499/discourse_development",
        "DATABASE_POOL_SIZE": "5",
        "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=15000",
        "DATABASE_READONLY": "1",
        "TMPDIR": str(output / "tmp"),
        "XDG_CACHE_HOME": str(output / "xdg-cache"),
    })
    return env


PREFLIGHT = r'''require "json"
require ENV.fetch("FIDELITY_ORACLE_GUARD")
raise "read-only transaction not forced" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
rejections = []
[["127.0.0.1", 6399], ["127.0.0.1", 6400], ["127.0.0.2", Integer(ENV.fetch("FIDELITY_VALKEY_PORT"))]].each do |host, port|
  begin
    Redis.new(host: host, port: port).ping
    raise "unsafe Redis endpoint accepted: #{host}:#{port}"
  rescue FidelityOracleIsolation::UnsafeEndpoint => error
    rejections << error.class.name
  end
end
begin
  Redis.new(path: "/tmp/fidelity-unowned.sock").ping
  raise "unowned Redis Unix socket accepted"
rescue FidelityOracleIsolation::UnsafeEndpoint => error
  rejections << error.class.name
end
begin
  PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development",
                         options: "-c default_transaction_read_only=off")
  raise "writable PG options accepted"
rescue FidelityOracleIsolation::UnsafeEndpoint => error
  rejections << error.class.name
end
begin
  PG::Connection.connect(host: "127.0.0.1", port: "5432", dbname: "discourse_development")
  raise "non-task PG port accepted"
rescue FidelityOracleIsolation::UnsafeEndpoint => error
  rejections << error.class.name
end
pg = PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")
raise "task PG not read-only" unless pg.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "on"
pg.close
redis = Redis.new(url: ENV.fetch("REDIS_URL"))
key = "settings-staging:preflight:#{Process.pid}"
redis.set(key, "fixture-only")
raise "private fixture write failed" unless redis.get(key) == "fixture-only"
redis.del(key)
puts JSON.generate({negative_redis_controls: rejections[0, 4].length, negative_pg_controls: rejections[4, 6].length,
                    task_pg_readonly: true, private_valkey_read_write_delete: true})
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path,
                        help="read-only Roundhouse project root containing discourse/ and run/bundle")
    parser.add_argument("--output", required=True, type=Path,
                        help="new isolated evidence directory; never reused or cleared")
    parser.add_argument("--bundle-path", type=Path, help="existing installed Bundler path (default: ROOT/run/bundle)")
    parser.add_argument("--ruby-version", default="4.0.9", help="already-installed mise Ruby version; no auto-install")
    frontend_inputs = parser.add_mutually_exclusive_group()
    frontend_inputs.add_argument("--build-frontend-assets", action="store_true",
                                 help="run one bounded original Rolldown production build in the private app archive before Rails trace")
    frontend_inputs.add_argument("--frontend-build-artifact", type=Path,
                                 help="reuse a verified built dist from an existing Fidelity build run; validate provenance and every output hash")
    parser.add_argument("--private-pg-manifest", type=Path, help="explicit authorized owned private PG fixture; default remains shared read-only")
    args = parser.parse_args()
    root = args.root.resolve()
    discourse_repo = root / "discourse"
    output = args.output.resolve()
    bundle_path = (args.bundle_path or root / "run/bundle").resolve()
    if not discourse_repo.is_dir() or not (discourse_repo / ".git").exists():
        parser.error("--root must contain the original discourse git checkout")
    if not bundle_path.is_dir():
        parser.error("--bundle-path must point to an existing installed bundle; no install is attempted")
    if output.exists():
        parser.error("--output must not already exist; this tool never overwrites prior evidence")
    if output == root or root in output.parents or output in root.parents:
        parser.error("--output must be a disjoint Fidelity-owned path, not the source project")
    output.mkdir(parents=True)
    (output / "tmp").mkdir()
    (output / "xdg-cache").mkdir()
    evidence = {"status": "in_progress", "source_revision": PIN, "source_root_read_only": str(discourse_repo),
                "output": str(output), "mutable_rails_root": str(output / "discourse"), "commands": []}
    (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")
    discourse = output / "discourse"
    discourse.mkdir()

    # Extract only the pinned tracked original source into the owned output tree.
    source_hashes = extract_pinned_source(discourse_repo, discourse)
    evidence["original_source_hashes"] = source_hashes
    evidence["source_checkout_not_modified"] = True
    (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")

    frontend_state: dict[str, object] = {
        "status": "not_copied",
        "detail": "frontend dependencies are staged only for an explicit build or verified asset reuse",
    }
    if args.build_frontend_assets or args.frontend_build_artifact:
        # Exact installed dependencies are needed by the real Rails bundle
        # verification and any original on-demand asset processors. Asset reuse
        # skips Rolldown itself but still stages those runtime inputs privately.
        source_modules = discourse_repo / "node_modules"
        copied_modules = discourse / "node_modules"
        source_lock = (discourse / "pnpm-lock.yaml").read_bytes()
        installed_lock = source_modules / ".pnpm/lock.yaml"
        frontend_state = {"source": str(source_modules)}
        if not source_modules.is_dir() or not installed_lock.is_file():
            frontend_state["status"] = "missing"
            frontend_state["detail"] = "original ignored node_modules unavailable; no install attempted"
        else:
            expected_installed_lock = expected_installed_pnpm_lock(source_lock)
            actual_installed_lock = installed_lock.read_bytes()
            frontend_state["expected_lock_sha256"] = sha(expected_installed_lock)
            frontend_state["observed_lock_sha256"] = sha(actual_installed_lock)
            frontend_state["installed_lock_bytes"] = len(actual_installed_lock)
            if actual_installed_lock == expected_installed_lock:
                symlink_proof = copy_dependency_tree(source_modules, copied_modules, discourse_repo, discourse)
                if (copied_modules / ".pnpm/lock.yaml").read_bytes() != expected_installed_lock:
                    raise RuntimeError("private node_modules copy failed lock-byte verification")
                frontend_state.update(status="matched_and_copied", copied=True,
                                      copy_method="private copy preserving verified symlinks",
                                      **symlink_proof)
            else:
                frontend_state["status"] = "present_but_mismatched"
                frontend_state["copied"] = False
                frontend_state["detail"] = "ignored node_modules does not match pinned pnpm-lock; omitted without install or substitution"
        frontend_modules = discourse_repo / "frontend/discourse/node_modules"
        if frontend_state.get("status") == "matched_and_copied":
            if not frontend_modules.is_dir():
                frontend_state["frontend_node_modules"] = {"status": "missing"}
            else:
                copied_frontend = discourse / "frontend/discourse/node_modules"
                copy_proof = copy_dependency_tree(frontend_modules, copied_frontend, discourse_repo, discourse)
                shutil.rmtree(copied_frontend)
                staged_proof = stage_frontend_node_modules(frontend_modules, copied_frontend,
                                                           discourse_repo, discourse)
                frontend_state["frontend_node_modules"] = {
                    "status": "copied_and_verified",
                    **copy_proof,
                    "staging_layout": "isolated absolute links to private archive package targets",
                    "staged_symlink_count": staged_proof["symlink_count"],
                    "staged_symlink_targets_verified": staged_proof["symlink_targets_verified"],
                }
                workspace_dependencies = copy_workspace_dependency_trees(
                    discourse_repo, discourse, {"frontend/discourse/node_modules"}
                )
                frontend_state["workspace_node_modules"] = {
                    "status": "copied_and_verified",
                    "workspace_count": len(workspace_dependencies),
                    "trees": workspace_dependencies,
                }
    evidence["frontend_dependency_tree"] = frontend_state
    (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")

    mise = shutil.which("mise") or "/home/agent/.local/bin/mise"
    ruby = subprocess.run([mise, "where", f"ruby@{args.ruby_version}"], text=True, capture_output=True)
    if ruby.returncode:
        raise RuntimeError(f"requested mise Ruby {args.ruby_version} is not installed; no install attempted")
    prefix = [mise, "exec", "--no-deps", f"ruby@{args.ruby_version}", "--"]
    env = make_env(root, output, discourse, bundle_path)
    private_pg = None
    if args.private_pg_manifest:
        manifest_path = args.private_pg_manifest.resolve()
        private_pg = json.loads(manifest_path.read_text())
        if private_pg.get("kind") != "owned_disposable_html_oracle_pg" or int(private_pg.get("port", 5499)) == 5499:
            raise RuntimeError("unrecognized/nonprivate PostgreSQL manifest")
        if Path(private_pg["data_directory"]).resolve() != manifest_path.parent / "pg-data":
            raise RuntimeError("private PG data directory is outside owned fixture")
        from urllib.parse import urlencode
        env.update(FIDELITY_PRIVATE_PG_MANIFEST=str(manifest_path),
                   FIDELITY_PRIVATE_PG_WRITE_LOG=str(output / "private-pg-writes.jsonl"),
                   PGHOST=private_pg["socket_directory"], PGPORT=str(private_pg["port"]),
                   PGUSER=private_pg["user"], PGDATABASE=private_pg["database"],
                   PGOPTIONS="-c statement_timeout=15000", DATABASE_READONLY="0",
                   DATABASE_URL="postgres:///" + private_pg["database"] + "?" + urlencode({
                       "host": private_pg["socket_directory"], "port": private_pg["port"], "user": private_pg["user"]}))
        for key in ("PGSERVICE", "PGSERVICEFILE", "PGHOSTADDR"):
            env.pop(key, None)
        evidence["private_pg_manifest"] = private_pg
    else:
        env.pop("FIDELITY_PRIVATE_PG_MANIFEST", None)
    # `mise exec` injects the project-selected Ruby, while `BUNDLE_GEMFILE`
    # points into the private archive so Bundler itself cannot write source.
    check = subprocess.run(prefix + ["bundle", "check"], cwd=discourse, env=env,
                           text=True, capture_output=True)
    evidence["bundle_check"] = {"returncode": check.returncode, "stdout": check.stdout.strip(),
                               "stderr": check.stderr.strip(), "ruby": args.ruby_version,
                               "bundle_path": str(bundle_path)}
    if check.returncode:
        evidence["status"] = "blocked_bundle"
        evidence["first_blocker"] = "installed pinned Rails dependencies unavailable; no install attempted"
        (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")
        raise RuntimeError(f"bundle check failed; see {output / 'state.json'}")

    if args.build_frontend_assets or args.frontend_build_artifact:
        try:
            if args.build_frontend_assets:
                if frontend_state.get("status") != "matched_and_copied" or \
                   frontend_state.get("frontend_node_modules", {}).get("status") != "copied_and_verified":
                    raise RuntimeError("exact root and frontend dependencies were not privately copied and verified")
                build_record = run_frontend_asset_build(discourse, output, timeout_seconds=600)
            else:
                build_record = reuse_verified_frontend_build(args.frontend_build_artifact, discourse, output)
                (output / "frontend-asset-build.json").write_text(json.dumps(build_record, indent=2) + "\n")
            asset_summary = {
                "status": build_record["status"],
                "record": str(output / "frontend-asset-build.json"),
                "manifest_sha256": build_record["manifest_sha256"],
                "output_file_count": build_record["output_file_count"],
                "output_bytes": build_record["output_bytes"],
            }
            for field in ("injected_network_syscall_count", "kernel_denied_io_uring_count", "artifact_source"):
                if field in build_record:
                    asset_summary[field] = build_record[field]
            evidence["frontend_asset_build"] = asset_summary
            (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")
        except Exception as error:
            build_record_path = output / "frontend-asset-build.json"
            build_summary = {"status": "failed", "error_class": type(error).__name__, "error": str(error)}
            if build_record_path.is_file():
                build_summary["record"] = str(build_record_path)
                try:
                    previous_build_record = json.loads(build_record_path.read_text())
                    build_summary["build_status"] = previous_build_record.get("status")
                    build_summary["returncode"] = previous_build_record.get("returncode")
                    build_summary["elapsed_seconds"] = previous_build_record.get("elapsed_seconds")
                except json.JSONDecodeError:
                    pass
            evidence["frontend_asset_build"] = build_summary
            evidence["status"] = "frontend_build_failed"
            (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")
            raise

    # Start only the existing task-owned private Valkey fixture. The oracle
    # isolation helpers validate its PID/config before any client dispatch.
    from oracle_sandbox import ValkeySandbox
    sandbox = ValkeySandbox(output / "valkey", evidence_dir=output)
    short_tmp = Path(tempfile.mkdtemp(prefix="rhsettings-"))
    short_tmp.rmdir()
    short_tmp.symlink_to(output / "tmp", target_is_directory=True)
    try:
        with sandbox:
            env.update(sandbox.environment)
            env["TMPDIR"] = str(short_tmp)
            # Persist phase-aware effect logs directly under this output path.
            env["FIDELITY_ORACLE_PHASE"] = "preflight"
            preflight_source = PREFLIGHT
            if private_pg:
                preflight_source = preflight_source.replace(
                    'raise "read-only transaction not forced" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")',
                    'FidelityPrivatePG.manifest!')
                preflight_source = preflight_source.replace(
                    'pg = PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")',
                    'pg = PG::Connection.connect(host: ENV.fetch("PGHOST"), port: ENV.fetch("PGPORT"), dbname: "discourse_development")')
                preflight_source = preflight_source.replace(
                    'raise "task PG not read-only" unless pg.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "on"',
                    'raise "private PG not writable" unless pg.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "off"\n'
                    'pg.exec("BEGIN"); pg.exec("CREATE TEMP TABLE oracle_private_write_probe (n integer)"); '
                    'pg.exec("INSERT INTO oracle_private_write_probe VALUES (42)"); '
                    'raise "private fixture effect absent" unless pg.exec("SELECT n FROM oracle_private_write_probe").getvalue(0,0) == "42"; pg.exec("ROLLBACK")')
                preflight_source = preflight_source.replace("task_pg_readonly: true", "owned_private_pg_writable: true")
            command = prefix + ["bundle", "exec", "ruby", "-e", preflight_source,
                                "--", str(HERE / "tools/oracle_isolation.rb")]
            preflight_rc = run(command, cwd=discourse, env=env,
                               stdout=output / "preflight.stdout", stderr=output / "preflight.stderr")
            evidence["preflight"] = {"returncode": preflight_rc,
                                     "stdout": (output / "preflight.stdout").read_text().strip(),
                                     "stderr": (output / "preflight.stderr").read_text().strip()}
            if preflight_rc:
                raise RuntimeError("endpoint/readonly preflight failed")

            env["FIDELITY_ORACLE_PHASE"] = "boot"
            trace_rc = run(prefix + ["bundle", "exec", "ruby", str(HERE / "tools/original_latest_trace_consumer.rb")],
                           cwd=discourse, env=env, stdout=output / "trace.stdout", stderr=output / "trace.stderr")
            evidence["trace_returncode"] = trace_rc
            evidence["trace_stdout"] = (output / "trace.stdout").read_text().strip()
            evidence["trace_stderr"] = (output / "trace.stderr").read_text().strip()
            if (output / "trace.json").is_file():
                trace = json.loads((output / "trace.json").read_text())
                evidence["trace_summary"] = {
                    "stage": trace.get("stage"), "page_json_statuses": trace.get("page_json_statuses"),
                    "html_phase": next((p.get("result") for p in trace.get("phases", []) if p.get("name") == "request_html"), None),
                    "setting_call_count": len(trace.get("site_setting_calls", [])),
                    "method_event_count": len(trace.get("methods", [])),
                    "preloader_source_requirements": trace.get("preloader_source_requirements"),
                    "plugin_names": trace.get("original_plugin_names"),
                    "external_dispatch_attempts": trace.get("external_dispatch_attempts"),
                    "raised_exceptions": trace.get("raised_exceptions"),
                    "failures": trace.get("failures"),
                }
            pg_log = output / "pg-connections.jsonl"
            if pg_log.exists():
                connections = [json.loads(line) for line in pg_log.read_text().splitlines() if line]
                evidence["pg_connections"] = connections
                if private_pg:
                    valid_connections = bool(connections) and all(
                        row.get("database") == private_pg["database"] and row.get("address") == private_pg["socket_directory"] and
                        row.get("port") == private_pg["port"] and row.get("default_transaction_read_only") == "off" and
                        row.get("private_owned_fixture") is True for row in connections)
                else:
                    valid_connections = bool(connections) and all(
                        row.get("database") == "discourse_development" and row.get("address") == "127.0.0.1" and
                        row.get("port") == 5499 and row.get("default_transaction_read_only") == "on" for row in connections)
                if not valid_connections:
                    raise RuntimeError("one or more original Rails PG connections failed the selected endpoint proof")
            if private_pg and (output / "private-pg-writes.jsonl").exists():
                evidence["private_pg_write_count"] = len((output / "private-pg-writes.jsonl").read_text().splitlines())
            writes = output / "valkey-writes.jsonl"
            if writes.exists():
                records = [json.loads(line) for line in writes.read_text().splitlines() if line]
                evidence["valkey_effects"] = [{"phase": r.get("phase"), "command": r.get("command"),
                                               "key": r.get("key"), "keys": r.get("keys"), "caller": r.get("caller", [])}
                                              for r in records if r.get("stage") == "successful_reply"]
            evidence["endpoint_rejections"] = [json.loads(line) for line in (output / "endpoint-rejections.jsonl").read_text().splitlines()]
            evidence["valkey_fixture"] = json.loads(sandbox.evidence_path.read_text())
            evidence["valkey_cleanup_verified"] = sandbox.cleanup_complete
            evidence["status"] = "traced" if trace_rc == 0 else "trace_incomplete"
    finally:
        if sandbox.evidence_path.exists():
            evidence["valkey_fixture"] = json.loads(sandbox.evidence_path.read_text())
            evidence["valkey_cleanup_verified"] = sandbox.cleanup_complete
        evidence["source_checkout_not_modified"] = not subprocess.check_output(
            ["git", "-C", str(discourse_repo), "status", "--porcelain"], text=True)
        if short_tmp.is_symlink():
            short_tmp.unlink()
        (output / "state.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"TRACE OUTPUT: {output}")
    print(f"STATUS: {evidence['status']}; PG connections={len(evidence.get('pg_connections', []))}; "
          f"Valkey cleanup={evidence.get('valkey_cleanup_verified')}")
    return 0 if evidence["status"] == "traced" and evidence.get("valkey_cleanup_verified") else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"TRACE HARNESS FAILED: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
