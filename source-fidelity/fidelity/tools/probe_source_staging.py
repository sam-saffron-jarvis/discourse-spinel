#!/usr/bin/env python3
"""Reject unsafe finite-source staging shortcuts; NOT activation acceptance."""
import argparse
import json
from pathlib import Path
import sys

from verify import Run, ROOT, HERE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, required=True, help="actual successful original activation observation evidence")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = Run("probe-source-staging")
    run.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4")
    run.evidence.update(stage="semantic rejection audit of whole original finite script staging candidates", broader019_accepted=False,
                        native_activation_accepted=False, scripts_executed=False)
    try:
        run.provenance()
        run.command("reduced-semantics", ["ruby", HERE / "test/source_staging_semantics_test.rb"], timeout=30)
        _, output = run.command("whole-source-audit", ["ruby", HERE / "tools/audit_plugin_staging.rb", HERE / "source/discourse", args.trace.resolve()], timeout=30)
        audit = json.loads(output)
        assert audit["accepted"] is False and len(audit["scripts"]) == 3
        assert all(not script["native_executed"] and not script["semantic_equivalence_proved"] for script in audit["scripts"])
        run.evidence["staging_audit"] = audit
        run.provenance()
        run.evidence["status"] = "rejected_unproved_staging_candidates_NOT_activation"
        run.save()
        print(f"REJECTED unproved block/hoisting/Proc shortcuts; NOT activation proof. Evidence: {run.path}")
        return 0
    except Exception as error:
        import traceback
        traceback.print_exc()
        run.evidence.update(status="failed_semantic_audit", error=repr(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
