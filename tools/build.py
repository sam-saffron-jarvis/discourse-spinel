#!/usr/bin/env python3
"""Measure the small Spinel build, its input graph, and peak *single-child* RSS.

ru_maxrss is not summed across parallel C compiler processes. No whole-app
compiler input, survey, compiler rebuild or profiling loop is invoked here.
"""
import json
import os
import pathlib
import re
import resource
import shlex
import subprocess
import time

build = pathlib.Path("build")
(build / "tmp").mkdir(parents=True, exist_ok=True)
os.environ["TMPDIR"] = str((build / "tmp").resolve())
binary = build / "bin/discourse"
previous_mtime = binary.stat().st_mtime_ns if binary.exists() else None
# spin currently checks the entrypoint mtime, not changed required/vendor files.
# This is a measured build command: force our OWN executable to be rebuilt so
# a newly vendored profiler core can never silently run an older native binary.
binary.unlink(missing_ok=True)
start = time.monotonic()
with (build / "compile.stdout").open("w") as stdout, (build / "compile.stderr").open("w") as stderr:
    result = subprocess.run(["spin", "build", "discourse"], stdout=stdout, stderr=stderr)
stats = {"wall_seconds": time.monotonic() - start,
         "max_child_rss_kib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
         "rss_definition": "maximum single child/descendant RSS, not aggregate parallel memory",
         "exit_code": result.returncode}
if result.returncode == 0:
    binary = build / "bin/discourse"
    with binary.open("rb") as executable:
        if executable.read(4) != b"\x7fELF":
            raise SystemExit("build/bin/discourse is not a native ELF")
    flags = shlex.split(subprocess.check_output(["spin", "flags"], text=True))
    graph = subprocess.check_output(["spinel", "--dump-load-graph", *flags, "bin/discourse.rb"], text=True)
    (build / "load-graph.txt").write_text(graph)
    inputs = [pathlib.Path(p) for p in re.findall(r"^file \d+ (.+)$", graph, re.M)]
    project_inputs = [p for p in inputs if p.is_relative_to(pathlib.Path.cwd())]
    stats.update(compiler_input_files=len(inputs), compiler_input_bytes=sum(p.stat().st_size for p in inputs),
                 project_input_files=len(project_inputs), project_input_bytes=sum(p.stat().st_size for p in project_inputs),
                 binary_bytes=binary.stat().st_size,
                 binary_rebuilt=binary.stat().st_mtime_ns != previous_mtime,
                 runtime_data_bytes=sum(pathlib.Path(p).stat().st_size for p in ["data/emoji-unicode.json", "data/emoji-existence.json", "reference/client-settings-contract.json"]),
                 emoji_existence_metadata_bytes=pathlib.Path("data/emoji-existence.json").stat().st_size,
                 unicode_metadata_bytes=pathlib.Path("data/emoji-unicode.json").stat().st_size,
                 client_settings_metadata_bytes=pathlib.Path("reference/client-settings-contract.json").stat().st_size,
                 browser_asset_files=sum(p.is_file() for p in pathlib.Path("build/assets").rglob("*")),
                 browser_asset_bytes=sum(p.stat().st_size for p in pathlib.Path("build/assets").rglob("*") if p.is_file()),
                 staged_media_bytes=sum(p.stat().st_size for p in pathlib.Path("build/media").rglob("*") if p.is_file()),
                 spinel_version=subprocess.run(["spinel", "--version"], capture_output=True, text=True).stdout.strip())
(build / "compile.json").write_text(json.dumps(stats, indent=2) + "\n")
print(json.dumps(stats, indent=2))
if result.returncode:
    print((build / "compile.stderr").read_text())
raise SystemExit(result.returncode)
