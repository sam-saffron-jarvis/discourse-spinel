#!/usr/bin/env python3
"""Original no-plugin multisite namespace/patch diagnostic, NEVER native inputs.

Uses the existing guarded Rails oracle and owned disposable Valkey fixture.
No PG writes, altered source, provider replacement or unverified native carrier.
"""
import json
import os
import subprocess

from probe_core_no_plugins import CoreNoPluginsRun
from verify import HERE, ROOT, PIN, digest


def validate_boundary(proof):
    assert proof["successful_oracle"]
    assert proof["final_same_namespace_object"]
    lifecycle = proof["lifecycle"]
    assert lifecycle and not lifecycle[0]["current_db_present"] and not lifecycle[0]["default_present"]
    assert all(event["same_namespace_object"] for event in lifecycle)
    patch = [event for event in lifecycle if event["source"][0].endswith("/lib/freedom_patches/rails_multisite.rb")]
    assert patch and patch[-1]["safe_each_present"]
    settings = [event for event in proof["initializer_points"] if event["source"][0].endswith("/005-site_settings.rb")]
    assert settings and all(event["safe_each_present"] for event in settings)
    assert patch[-1]["order"] < min(event["order"] for event in settings)
    attempts = proof["initializer_require_attempts"]
    census = proof["freedom_patch_source_census"]
    assert census and all(path.endswith(".rb") and len(sha) == 64 for path, sha in census.items())
    assert [event["order"] for event in attempts] == sorted({event["order"] for event in attempts})
    immediate = [event for event in attempts if event["target"].endswith("/freedom_patches/rails_multisite.rb")]
    deferred = [event for event in attempts if event not in immediate]
    assert len(immediate) == 1 and not immediate[0]["safe_each_present"]
    assert immediate[0]["order"] < patch[-1]["order"]
    assert deferred and all(event["safe_each_present"] for event in deferred)
    assert len(deferred) == len(census) - 1
    assert sorted(event["target"] for event in attempts) == sorted(census)
    # Registration occurs in initializer order; actual preparation then runs
    # 002's deferred requires BEFORE 005's settings callback, not before every
    # source point in 005 (which also contains that deferred callback body).
    callbacks = [event for event in settings if event["event"] == "b_call"]
    assert callbacks
    assert min(event["order"] for event in settings) < min(event["order"] for event in deferred)
    assert max(event["order"] for event in deferred) < min(event["order"] for event in callbacks)
    assert all(event["source"][0].endswith("/002-freedom_patches.rb") for event in attempts)
    assert proof["callable_descriptors"]["current_db"]["arity"] == -1
    assert proof["callable_descriptors"]["safe_each_connection"]["source"][0].endswith("/lib/freedom_patches/rails_multisite.rb")
    returns = [event for event in proof["all_selected_return_types"] if event["method"] == "instance"]
    assert returns and not any(event["module_value"] for event in returns)
    assert all(event["result_class"].startswith("RailsMultisite::ConnectionManagement") for event in returns)


class MultisiteRun(CoreNoPluginsRun):
    def oracle_arguments(self):
        return [HERE / "tools/core_multisite_oracle.rb", HERE / "tools/core_no_plugins_reference_consumer.rb", self.path / "probe.rb"]


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = MultisiteRun()
    try:
        # Includes the original read-only Vips helper source attestation. Missing
        # attestation is a real guard failure, never permission to skip its effect.
        run.provenance()
        run.initial_reference()
        lines = (run.path / "rails-oracle.stdout").read_text().splitlines()
        prefix = "FIDELITY_CORE_MULTISITE "
        matches = [json.loads(line.removeprefix(prefix)) for line in lines if line.startswith(prefix)]
        assert len(matches) == 1
        proof = matches[0]
        validate_boundary(proof)
        # Independently attest the COMPLETE original callback source census.
        # These source hashes are diagnostic evidence, never native inputs.
        original = ROOT / "discourse"
        expected = subprocess.check_output(["git", "-C", str(original), "ls-tree", "--name-only", PIN,
                                            "lib/freedom_patches/"]).decode().splitlines()
        expected = [path for path in expected if path.endswith(".rb")]
        assert set(proof["freedom_patch_source_census"]) == {str(original / path) for path in expected}
        for path in expected:
            pinned = subprocess.check_output(["git", "-C", str(original), "show", f"{PIN}:{path}"])
            assert (original / path).read_bytes() == pinned
            assert proof["freedom_patch_source_census"][str(original / path)] == digest(pinned)
        run.evidence["original_multisite_boundary"] = proof
        run.evidence.update(scope="original no-plugin multisite namespace/load-order/callable diagnostic ONLY; NOT a full provider effect trace",
                            native_equal=False, native_carrier_accepted=False,
                            observed_values_or_types_used_as_native_inputs=False,
                            status="original_multisite_boundary_passed; core_native_query_page_NOT_accepted")
        run.provenance()
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
