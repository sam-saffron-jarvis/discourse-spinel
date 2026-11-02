#!/usr/bin/env python3
"""Build actual Rails/compiled-NativeTopic discourse-details fixtures.

Callable by the parent browser test as build_fixtures(); CLI invocation is
`python3 test/details_source_test.py`. All generated artifacts stay in build/.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT.parent
DISCOURSE = RUN_ROOT / "discourse"
OUT = ROOT / "build" / "details"
DATABASE_URL = "postgres://discourse@127.0.0.1:5499/discourse_development"
REDIS_URL = "redis://127.0.0.1:6399/0"


def task_env():
    env = dict(os.environ)
    env.update({
        "DATABASE_URL": DATABASE_URL,
        "REDIS_URL": REDIS_URL,
        "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=15000",
        "TMPDIR": str(ROOT / "build" / "tmp"),
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    if env["DATABASE_URL"] != DATABASE_URL or env["REDIS_URL"] != REDIS_URL:
        raise RuntimeError("task DB/Valkey identity mismatch")
    return env


def interrupted(number, _frame):
    raise SystemExit(128 + number)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def run(argv, cwd, env):
    child = subprocess.Popen(argv, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = child.communicate(timeout=170)
    except BaseException:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        raise
    if child.returncode:
        raise RuntimeError(
            f"command failed ({child.returncode}): {argv!r}\n"
            f"stdout:\n{stdout[-5000:]}\nstderr:\n{stderr[-8000:]}"
        )
    if stdout:
        print(stdout, end="")
    if stderr:
        print(stderr, end="", file=__import__("sys").stderr)


def build_fixtures():
    """Capture actual Rails cooker output, then compile and run NativeTopic CTE test."""
    OUT.mkdir(parents=True, exist_ok=True)
    # Spin caches by entrypoint timestamp. Remove only artifacts owned by this
    # fixture so each invocation compiles and reruns the current source.
    for name in ("source-fixtures.json", "native-fixtures.json", "live-inventory.json"):
        (OUT / name).unlink(missing_ok=True)
    for name in ("details_native", "details_native.cruby"):
        (ROOT / "build" / "test" / name).unlink(missing_ok=True)
    env = task_env()
    run(["bin/rails", "runner", str(ROOT / "test" / "details_source.rb")], DISCOURSE, env)
    run(["spin", "test", "test/details_native.rb"], ROOT, env)

    source = json.loads((OUT / "source-fixtures.json").read_text())
    native = json.loads((OUT / "native-fixtures.json").read_text())
    if not source.get("read_only") or not native.get("read_only") or not native.get("synthetic"):
        raise AssertionError("fixture read-only/synthetic marker missing")
    source_cases = {entry["name"]: entry["cooked"] for entry in source["cases"]}
    required = {'closed', 'open', 'nested', 'summary_escaping', 'sanitizer_elided', 'title_open_unsupported_attrs', 'reader_combined'}
    if set(source_cases) != required:
        raise AssertionError(('missing labeled source coverage', set(source_cases), required))
    for setting in ('enabled', 'disabled'):
        stored = {entry['name']: entry['cooked'] for entry in source['stored_serializer_by_setting'][setting]}
        if stored != source_cases:
            raise AssertionError('actual source stored getter differs from cooked fixtures')
    native_cases = {entry["name"]: entry["cooked"] for entry in native["cases"]}
    if source_cases != native_cases or not all(entry["source_cooked_match"] for entry in native["cases"]):
        raise AssertionError("compiled topic cooked values differ from actual source cooker")
    inventory = {
        "read_only": True,
        "database_url": DATABASE_URL,
        "details_enabled_default": source["source_setting"]["default"],
        "details_enabled_live": source["source_setting"]["live"],
        "details_posts": source["live_inventory"]["details_posts"],
        "source_setting": source["source_setting"],
        "counts": source["live_inventory"],
    }
    (OUT / "live-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    return {
        "source": OUT / "source-fixtures.json",
        "native": OUT / "native-fixtures.json",
        "live_inventory": OUT / "live-inventory.json",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    paths = build_fixtures()
    print("details fixtures:")
    for name, path in paths.items():
        print(f"  {name}: {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
