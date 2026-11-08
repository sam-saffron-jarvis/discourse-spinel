#!/usr/bin/env python3
"""Separate ORIGINAL -> PATCHED Rails core-only integration proof.

No full-native/page acceptance. All endpoints, original source locks and owned
fixture cleanup controls from the established oracle are retained unchanged.
"""
import json
import os
from pathlib import Path
import shutil

from probe_core_no_plugins import CoreNoPluginsRun
from verify import HERE, ROOT, digest, equal_records


class HybridRailsRun(CoreNoPluginsRun):
    def oracle(self):
        if not hasattr(self, "candidate_root"):
            return super().oracle()
        # The unchanged legacy oracle calls this metadata "original files".
        # In THIS separately labelled patched profile, check actual candidate
        # inputs against their own manifest, never against a falsified baseline.
        baseline = dict(self.evidence["source_hashes"])
        expected = dict(baseline)
        applied = self.evidence["candidate_source_sha256"]
        for name, sha in applied.items():
            relative = name.removeprefix("discourse/")
            assert digest((self.candidate_root / relative).read_bytes()) == sha
            if relative in expected:
                expected[relative] = sha
        self.evidence["immutable_reference_source_sha256"] = baseline
        self.evidence["patched_oracle_expected_source_sha256"] = expected
        self.evidence["legacy_metadata_scope"] = "complete_original_files is a legacy key: this oracle loads manifested PATCHED files; immutable reference hashes are retained separately"
        self.evidence["source_hashes"] = expected
        try:
            return super().oracle()
        finally:
            self.evidence["source_hashes"] = baseline
            for name, sha in applied.items():
                assert digest((self.path / name).read_bytes()) == sha

    def oracle_application_root(self):
        return getattr(self, "candidate_root", ROOT / "discourse")

    def oracle_arguments(self):
        tools = getattr(self, "candidate_tools", HERE / "tools")
        return [tools / "core_no_plugins_oracle.rb", HERE / "tools/portable_rails_reference_consumer.rb",
                self.path / "probe.rb"]

    def command(self, name, argv, cwd=ROOT, **kwargs):
        if name == "rails-oracle" and hasattr(self, "candidate_root"):
            cwd = self.candidate_root
        return super().command(name, argv, cwd=cwd, **kwargs)


def read_proof(path):
    prefix = "FIDELITY_PORTABLE_RAILS "
    rows = [json.loads(line[len(prefix):]) for line in path.read_text().splitlines() if line.startswith(prefix)]
    assert len(rows) == 1
    return rows[0]


def materialize_candidate(run):
    # Exact sibling layout lets an UNCHANGED COPY of the isolation verifier
    # attest the candidate's still-pinned Vips sources and child ownership.
    # No configurable new helper endpoint/path authority is introduced.
    run.candidate_root = run.path / "discourse"
    run.command("clone-isolated-reference", ["git", "clone", "--shared", "--no-checkout",
                ROOT / "discourse", run.candidate_root], timeout=60)
    run.command("checkout-pinned-reference", ["git", "-C", run.candidate_root, "checkout", "--detach",
                "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"], timeout=60)
    manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
    applied = {}
    for name, expected in manifest["candidate_source_sha256"].items():
        source = HERE / "compat" / name
        assert digest(source.read_bytes()) == expected
        target = run.path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        assert digest(target.read_bytes()) == expected
        applied[name] = expected
    run.candidate_tools = run.path / "fidelity/tools"
    run.candidate_tools.mkdir(parents=True)
    verifier_hashes = {}
    for name in ("core_no_plugins_oracle.rb", "oracle.rb", "oracle_isolation.rb"):
        source = HERE / "tools" / name
        target = run.candidate_tools / name
        shutil.copyfile(source, target)
        assert source.read_bytes() == target.read_bytes()
        verifier_hashes[name] = digest(target.read_bytes())
    run.evidence["candidate_source_sha256"] = applied
    # Real existing server-side JS build outputs, not an invented frontend
    # manifest. The application's unchanged PrecompiledBundle recomputes its
    # input-content digest before selecting either file in the isolated clone.
    js_bundles = {}
    for directory in ("asset-processor", "pretty-text-processor"):
        for source in (ROOT / "discourse/tmp" / directory).glob("*.js"):
            relative = source.relative_to(ROOT / "discourse")
            target = run.candidate_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            assert source.read_bytes() == target.read_bytes()
            js_bundles[str(relative)] = digest(target.read_bytes())
    run.evidence["real_server_js_bundle_sha256"] = js_bundles
    run.evidence["unchanged_relocated_verifiers"] = verifier_hashes


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    original = HybridRailsRun()
    original.env.update(FIDELITY_CORE_HTTP_REFERENCE="1", FIDELITY_CORE_REFERENCE_DIRECTORY=str(original.path))
    original.evidence.update(profile="ORIGINAL reference for PATCHED hybrid Rails", core_latest_accepted=False)
    try:
        original.provenance()
        original.initial_reference()
        reference = read_proof(original.path / "rails-oracle.stdout")
        original.evidence.update(status="original_hybrid_comparison_reference_ONLY", settings_proof=reference)
    finally:
        original.save()
        print(f"Original evidence: {original.path}", flush=True)

    candidate = HybridRailsRun()
    candidate.env.update(FIDELITY_CORE_HTTP_REFERENCE="1", FIDELITY_CORE_REFERENCE_DIRECTORY=str(candidate.path))
    candidate.evidence.update(profile="PATCHED hybrid Rails core-no-plugins", original_reference=str(original.path),
                              native_full_site_setting_accepted=False, core_latest_accepted=False)
    try:
        candidate.provenance()
        materialize_candidate(candidate)
        candidate.initial_reference()
        actual = read_proof(candidate.path / "rails-oracle.stdout")
        assert actual["profile"] == "PATCHED hybrid core-no-plugins"
        assert "portable_scalar_readers.rb" in actual["scalar_getter_source"][0]
        assert "portable_rails_extension.rb" in actual["refresh_source"][0]
        assert "site_setting_extension.rb" in actual["special_getter_source"][0]
        equal_records(reference["records"], actual["records"])
        equal_records(original.evidence["actual_core_constructor_reference"], candidate.evidence["actual_core_constructor_reference"])
        # Compare actual original /latest.json serialization, not only getters.
        original_http = original.evidence["original_core_http_reference"]["requests"]
        candidate_http = candidate.evidence["original_core_http_reference"]["requests"]
        for path in original_http:
            assert original_http[path]["status"] == candidate_http[path]["status"]
            if path.endswith(".json"):
                assert original_http[path]["status"] == 200
                equal_records(original_http[path]["topic_ids"], candidate_http[path]["topic_ids"])
                equal_records(original_http[path]["top_level_keys"], candidate_http[path]["top_level_keys"])
                equal_records(original_http[path]["topic_keys"], candidate_http[path]["topic_keys"])
        # Compare the complete original serialized JSON (types/NULL/fields), not
        # just IDs or a hand-selected subset of the payload.
        equal_records(json.loads((original.path / "latest.json.response").read_text()),
                      json.loads((candidate.path / "latest.json.response").read_text()))
        corrupted = json.loads(json.dumps(actual["records"]))
        corrupted[0][3] = "deliberately wrong patched setting"
        try:
            equal_records(reference["records"], corrupted)
        except AssertionError:
            candidate.evidence["wrong_setting_negative_detected"] = True
        else:
            raise AssertionError("hybrid comparison accepted a wrong setting")
        for label in ("TopicPoster[unit attributes]", "TopicPoster[bad read key]", "TopicPoster[constructor parameters]"):
            corrupted = json.loads(json.dumps(actual["records"]))
            record = next(record for record in corrupted if record[0] == label)
            record[3] = "deliberately wrong poster contract"
            try:
                equal_records(reference["records"], corrupted)
            except AssertionError:
                candidate.evidence.setdefault("wrong_poster_contracts_rejected", []).append(label)
            else:
                raise AssertionError("hybrid comparison accepted a wrong poster contract: " + label)
        candidate.evidence.update(status="original_vs_PATCHED_Rails_hybrid_equal_ONLY", settings_proof=actual,
                                  settings_records_equal=len(actual["records"]),
                                  native_full_site_setting_accepted=False, core_latest_accepted=False)
    finally:
        candidate.save()
        print(f"Patched evidence: {candidate.path}", flush=True)


if __name__ == "__main__":
    main()
