"""Stage4 execution policy ONLY: exactly two readonly PG connections plus ONE
separately owned guarded cache connection, full raw trace retained. Historical
PG-only runners/gates are untouched. Other execution/type/scope controls below
retain the existing anonymous-security runner algorithms.
"""
import os
import json
import shutil
from pathlib import Path
from verify import ROOT, digest, equal_records


def validate_request_trace(trace, fixture):
    assert trace.count("execve(") == 1, "native spawned another process"
    connections = [line for line in trace.splitlines() if "connect(" in line]
    port = fixture["port"]
    assert type(port) is int and 0 < port < 65536 and port not in (5499, 6399)
    assert fixture["cleanup_complete"] is True and len(connections) == 3
    assert sum('htons(5499)' in line for line in connections) == 2
    assert sum(f'htons({port})' in line for line in connections) == 1
    assert all('inet_addr("127.0.0.1")' in line for line in connections), "unexpected native network endpoint"
    return {"execve_count": 1, "pg_connections": 2, "trace": "native.trace", "ruby_child": False,
        "cache_service_effects_in_selected_slice": True, "separately_owned_cache_connections": 1,
        "cache_fixture_cleanup_complete": True}


def execute_request_core(self):
    pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
    assert (pg_dir / "pg.rb").is_file(), "set SPINEL_PG_DIR to the existing spinel-pg checkout"
    self.evidence["pg_driver_sha256"] = {str(p.relative_to(pg_dir)): digest(p.read_bytes()) for p in sorted(pg_dir.rglob("*.rb"))}
    self.evidence["request_native_integer_profile"] = {"option": "--int-overflow=promote",
        "reason": "actual bundled IPAddr IPv6/default /0 masks require original Ruby 128-bit integer semantics",
        "all_earlier_typed_query_controls_retained": True}
    self.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--int-overflow=promote", "--rbs", self.path / "emitted",
                                  "-I", pg_dir, self.path / "entry.rb", "-o", self.path / "probe"])
    assert (self.path / "probe").read_bytes()[:4] == b"\x7fELF"
    self.evidence["native_elf_sha256"] = digest((self.path / "probe").read_bytes())
    self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], timeout=60)
    trace = (self.path / "native.trace").read_text()
    self.evidence["native_execution_path"] = validate_request_trace(trace, self.evidence["owned_cache_runtime_effects"]["native"])
    compat = self.path / "compat"
    shutil.copytree(self.path / "emitted", compat / "emitted")
    for name in ("entry.rb", "probe.rb"):
        shutil.copyfile(self.path / name, compat / name)
    shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
    native_hashes = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
    compat_hashes = {str(p.relative_to(compat / "emitted")): digest(p.read_bytes()) for p in (compat / "emitted").rglob("*.rb")}
    differences = [p for p in native_hashes if native_hashes[p] != compat_hashes[p]]
    assert differences == ["runtime/pg_driver.rb"]
    self.evidence["same_lowered_ruby"] = {"hashes": native_hashes, "platform_only_difference": differences,
        "entry_sha256": digest((self.path / "entry.rb").read_bytes()), "probe_sha256": digest((self.path / "probe.rb").read_bytes())}
    self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
    self.env["FIDELITY_NEGATIVE_SCOPE"] = "1"
    try:
        self.command("native-wrong-scope", [self.path / "probe"], timeout=60)
        self.command("compat-wrong-scope", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
    finally:
        del self.env["FIDELITY_NEGATIVE_SCOPE"]
    native = self.records("native")
    equal_records(native, self.records("compat"))
    equal_records(self.records("native-wrong-scope"), self.records("compat-wrong-scope"))
    assert any(r.get("kind") == "row" for r in native)
    rows = [r for r in native if r.get("kind") == "fixture"]
    assert [r["id"] for r in rows] == self.evidence["source_fixture"]["expected_ids"]
    assert [r["id"] for r in self.records("native-wrong-scope") if r.get("kind") == "fixture"] == self.evidence["source_fixture"]["wrong_scope_expected_ids"]
    assert next(r for r in rows if r["id"] == 107)["visible"] is None
    assert next(r for r in rows if r["id"] == 108)["category_id"] is None
    assert next(r for r in rows if r["id"] == 109)["category_name"] is None
    wrong = json.loads(json.dumps(native))
    next(r for r in wrong if r.get("kind") == "row")["visible"] = 1
    try:
        equal_records(native, wrong)
    except AssertionError:
        self.evidence["type_negative_control"] = True
    else:
        raise AssertionError("boolean/integer comparator control did not fail")
    self.evidence["query_observations"] = {name: [json.loads(line.removeprefix("FIDELITY_QUERY ")) for line in (self.path / f"{name}.stdout").read_text().splitlines() if line.startswith("FIDELITY_QUERY ")] for name in ("native", "compat")}
    assert self.evidence["query_observations"]["native"] == self.evidence["query_observations"]["compat"]
    self.save()
