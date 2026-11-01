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
                 runtime_data_bytes=pathlib.Path("data/emoji-unicode.json").stat().st_size,
                 spinel_version=subprocess.run(["spinel", "--version"], capture_output=True, text=True).stdout.strip())
(build / "compile.json").write_text(json.dumps(stats, indent=2) + "\n")
print(json.dumps(stats, indent=2))
if result.returncode:
    print((build / "compile.stderr").read_text())
raise SystemExit(result.returncode)
