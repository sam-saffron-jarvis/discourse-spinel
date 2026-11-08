#!/usr/bin/env python3
"""Compare the complete original patch's methods with shared IR AFTER boot.

Two separately owned full-Rails carriers. NOT native, standalone compatibility,
load-order equivalence or cold-cache parity; those claims remain unaccepted.
"""
import argparse
import json
import os
from pathlib import Path
import shutil

from probe_core_no_plugins import CoreNoPluginsRun
from verify import HERE, digest, equal_records


def validate_renderer(proof):
    """Control coverage only; NEVER application data or a native capability."""
    rows = proof["results"]
    assert len(rows) == 13, "callback/lifetime control omitted"
    assert proof["descriptors"] == {
        "safe_each_connection": {"arity": 0, "parameters": []},
        "each_active_connection": {"arity": 0, "parameters": [["block", "blk"]]},
    }
    for offset, branch in ((0, False), (6, True)):
        group = rows[offset:offset + 6]
        assert all(row["branch"] is branch for row in group)
        first, transfer = group[:2]
        assert len(first["callbacks"]) == 1
        site = first["callbacks"][0]
        assert len(site) == 3 and isinstance(site[0], str) and site[1:] == ["String", True]
        assert first["returned"] == "callback_result" and first["nonlocal"] == site[:2]
        assert transfer["no_block"] is None and transfer["block_break"] == "block_break_result"
        assert transfer["caught_throw"] == site[:2]
        for row, error in zip(group[2:], ("PG::ConnectionBad", "PG::UnableToSend", "PG::ServerError", "ArgumentError")):
            assert row["rescued_error"] == error
            assert row["callbacks"] == [site[:2]] and row["returned"] is None
        assert group[-1]["genuine_stderr_puts"] == [[True, "puts"]]
        assert proof["genuine_error_lines"][int(branch)] == (
            f"URGENT: Failed to initialize site {site[0]}: ArgumentError isolated standard callback fault")
    assert len(proof["genuine_error_lines"]) == 2
    lookup = rows[-1]
    assert isinstance(lookup["lookup_result"], str) and lookup["lookup_class"] == "String"
    assert lookup["literal_frozen"] is True and lookup["other_path"] is None


class RendererRun(CoreNoPluginsRun):
    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/core_multisite_renderer_consumer.rb", self.path / "probe.rb"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lowered", type=Path, required=True, help="complete patch Ruby exported from the audited original_multisite_boundary test")
    args = parser.parse_args()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    source = args.lowered.resolve()
    before = source.read_bytes()
    results = []
    for mode in ("original", "lowered"):
        run = RendererRun()
        run.provenance()
        if mode == "lowered":
            copy = run.path / "complete-patch-shared-ir.rb"
            shutil.copyfile(source, copy)
            run.env["FIDELITY_MULTISITE_LOWERED"] = str(copy)
        try:
            run.initial_reference()
            prefix = "FIDELITY_MULTISITE_RENDERER "
            records = [json.loads(line.removeprefix(prefix)) for line in (run.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith(prefix)]
            assert len(records) == 1
            assert source.read_bytes() == before
            # Keep actual STDERR output, not a stubbed logger or a value
            # reconstructed from exception observations. Backtraces retain
            # their original/generated source paths in each complete raw log.
            urgent = [line for line in (run.path / "rails-oracle.stderr").read_text().splitlines()
                      if line.startswith("URGENT: Failed to initialize site ")
                      and line.endswith(": ArgumentError isolated standard callback fault")]
            assert len(urgent) == 2, "genuine complete error line changed/omitted"
            records[0]["genuine_error_lines"] = urgent
            validate_renderer(records[0])
            run.evidence.update(multisite_postboot_renderer=records[0], lowered_patch_sha256=digest(before),
                                scope="separate full-Rails POSTBOOT patch renderer diagnostic ONLY",
                                native_equal=False, candidate_bootstrap_accepted=False,
                                observed_values_used_as_native_inputs=False)
            run.save()
            results.append((str(run.path), records[0]))
            print(mode, run.path)
        finally:
            run.save()
    comparison = {"scope": "separate full-Rails POSTBOOT renderer experiment ONLY; NOT native/bootstrap/cache proof",
                  "carriers": [item[0] for item in results], "lowered_patch_sha256": digest(before), "native_equal": False}
    output = Path(results[-1][0]) / "renderer-comparison.json"
    try:
        equal_records([results[0][1]["results"], results[0][1]["descriptors"], results[0][1]["genuine_error_lines"]],
                      [results[1][1]["results"], results[1][1]["descriptors"], results[1][1]["genuine_error_lines"]])
        comparison["renderer_equal"] = True
    except AssertionError:
        comparison.update(renderer_equal=False, original=results[0][1], lowered=results[1][1])
        raise
    finally:
        output.write_text(json.dumps(comparison, indent=2) + "\n")
        print("Comparison:", output)


if __name__ == "__main__":
    main()
