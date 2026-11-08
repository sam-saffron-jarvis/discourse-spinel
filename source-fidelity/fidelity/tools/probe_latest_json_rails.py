#!/usr/bin/env python3
"""Genuine original/shared Rails JSON matrix regression; NOT native acceptance."""
import json
import os
import re

from probe_portable_rails import HybridRailsRun, materialize_candidate, read_proof
from verify import HERE, equal_records


class JsonRailsRun(HybridRailsRun):
    def oracle_arguments(self):
        tools = getattr(self, "candidate_tools", HERE / "tools")
        return [tools / "core_no_plugins_oracle.rb", HERE / "tools/latest_json_request_reference_consumer.rb", self.path / "probe.rb"]


def report(run):
    prefix = "FIDELITY_JSON_REQUEST_REFERENCE "
    rows = [json.loads(line[len(prefix):]) for line in (run.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith(prefix)]
    assert len(rows) == 1
    return rows[0]


def comparable(report, *, expected_request_ids=None):
    rows = []
    profiler_ids = {}
    for index, row in enumerate(report["requests"]):
        headers = {key.lower(): value for key, value in row["headers"].items()}
        # Retain raw header in evidence; compare UUID structure, not fresh
        # cryptographic randomness. No other header is dropped/normalized.
        assert "x-request-id" in headers, "request middleware did not produce X-Request-Id"
        identifier = headers.pop("x-request-id")
        if expected_request_ids is not None and index in expected_request_ids:
            assert identifier == expected_request_ids[index], "supplied request ID was not sanitized/preserved exactly"
            headers["x-request-id"] = identifier
        else:
            assert re.fullmatch(r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", identifier)
        if "x-miniprofiler-ids" in headers or "profiler_proof" in row:
            proof = row["profiler_proof"]
            current = proof["current_id"]
            assert re.fullmatch(r"[0-9a-z]{1,20}", current), "invalid fresh profiler ID"
            assert current not in profiler_ids, "profiler reused a request ID"
            profiler_ids[current] = index
            unviewed = proof["ordered_unviewed_ids"]
            assert len(set(unviewed)) == len(unviewed) and all(value in profiler_ids for value in unviewed)
            limit = proof["max_traces_to_show"]
            assert type(limit) is int and limit > 0
            advertised = headers.get("x-miniprofiler-ids", "").split(",") if "x-miniprofiler-ids" in headers else []
            expected = list(dict.fromkeys([current] + unviewed))[:limit] if 200 <= row["status"] < 300 else []
            assert advertised == expected, "profiler header does not match current-first real store ranking"
            pages = proof["stored_pages"]
            assert [page["id"] for page in pages] == list(dict.fromkeys([current] + advertised)), "missing advertised stored record"
            for page in pages:
                assert page["request_method"] == "GET" and page["request_path"] == "/latest.json"
                assert type(page["sql_count"]) is int and page["sql_count"] >= 0
                assert "root" in page["fields"] and "request_path" in page["fields"]
                assert isinstance(page["root_name"], str) and isinstance(page["user"], str)
            if advertised:
                # Raw values/ranking are retained and verified against the
                # owned store above. Opaque IDs and expiry-score ties vary
                # across executions: compare current identity and prior-page
                # membership, NOT fabricated deterministic random bytes.
                headers["x-miniprofiler-ids"] = {"current_request": index,
                    "prior_requests": sorted(profiler_ids[value] for value in advertised[1:])}
        result = {"path": row["path"], "status": row["status"], "headers": headers, "body": row["body"]}
        if "request_effects" in row:
            effects = row["request_effects"]
            assert effects["processing_during_dispatch"] is True, "processing middleware did not surround dispatch"
            assert effects["processing_during_profiler_save"] is True, "processing middleware order did not surround real profiler save"
            assert effects["processing_after_dispatch"] is None, "processing middleware leaked thread context"
            assert effects["profiler_authorized_after_dispatch"] is True, "real controller did not authorize development profiler"
            layout = effects["application_layout_preloader"]
            assert layout["allocated"] is True, "real application layout preloader was omitted"
            assert layout["guardian_anonymous"] is True and layout["preloaded_empty"] is True
            assert layout["login_method"] is None and layout["theme_target"] in ("desktop", "mobile")
            assert layout["theme_id"] is None or type(layout["theme_id"]) is int
            fields = effects["profiler_snapshot_fields"]
            assert isinstance(fields, dict) and "Application version" in fields, "real profiler snapshot-field callback omitted"
            readonly = effects["readonly_state"]
            assert type(readonly["readonly"]) is bool and type(readonly["staff_writes_only"]) is bool, "readonly callback omitted or wrong state types"
            if 200 <= row["status"] < 300:
                if readonly["readonly"]:
                    assert headers.get("discourse-readonly") == "true", "readonly header callback omitted"
                else:
                    assert "discourse-readonly" not in headers, "false readonly mode advertised"
            assert type(effects["authorized_host_during_dispatch"]) is str and effects["authorized_host_during_dispatch"], "real host authorization did not run before controller"
            peer = effects["remote_ip_during_dispatch"]
            assert type(peer) is dict, "missing remote IP context"
            assert type(peer["value"]) is str and peer["value"] in ("127.0.0.1", "::1"), "wrong or missing direct remote IP"
            assert peer["lazy_class"] == "ActionDispatch::RemoteIp::GetIp", "real lazy RemoteIp middleware omitted/late"
            assert effects["request_id_visible_and_consistent"] is True, "request ID absent during controller or mismatched response"
            assert effects["request_locale"] == {"during_callbacks": "en", "after_dispatch": "fr"}, "locale scope omitted or not restored"
            result["request_effects"] = effects
        rows.append(result)
    return rows


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    runs = []
    try:
        for patched in (False, True):
            run = JsonRailsRun()
            runs.append(run)
            run.env["FIDELITY_JSON_REQUEST_REFERENCE_DIRECTORY"] = str(run.path)
            run.env["FIDELITY_JSON_REQUEST_BASE_CONSUMER"] = "settings"
            run.evidence.update(profile="shared Rails JSON matrix" if patched else "original Rails JSON matrix",
                                json_request_accepted=False, full_query_accepted=False, page_accepted=False)
            run.provenance()
            if patched:
                materialize_candidate(run)
            run.initial_reference()
            run.provenance()
            run.evidence["controller_request_reference"] = report(run)
            run.evidence["status"] = "PASSED_RAILS_REQUEST_REFERENCE_ONLY"
            run.save()
        equal_records(comparable(report(runs[0])), comparable(report(runs[1])))
        equal_records(runs[0].records("rails-oracle"), runs[1].records("rails-oracle"))
        equal_records(read_proof(runs[0].path / "rails-oracle.stdout")["records"],
                      read_proof(runs[1].path / "rails-oracle.stdout")["records"])
        runs[1].evidence.update(status="PASSED_SHARED_RAILS_REQUEST_MATRIX_NOT_NATIVE", original_reference=str(runs[0].path),
                               full_payload_status_headers_paging_and_400_equal=True)
        print("PASS genuine original/shared Rails request matrix ONLY; not native acceptance")
    except BaseException as error:
        if runs:
            runs[-1].evidence.update(status="FAILED_RAILS_JSON_MATRIX", error=repr(error))
        raise
    finally:
        for run in runs:
            run.save()
            print(run.path)


if __name__ == "__main__":
    main()
