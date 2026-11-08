"""Audit supplementary source-derived serializer components, never runtime data."""
import json
from pathlib import Path

from verify import HERE, digest

MANIFESTS = (
    "progressive/stage4/SERIALIZER_SOURCE_MANIFEST.json",
    "progressive/stage4/SERIALIZER_DECLARATIONS_MANIFEST.json",
    "progressive/stage4/READ_DEPENDENCIES_MANIFEST.json",
)


def audit(here=HERE):
    main = json.loads((here / "compat/MANIFEST.json").read_text())
    linked = main["supplementary_source_manifests"]
    reports = {}
    for name in MANIFESTS:
        path = here / name
        assert digest(path.read_bytes()) == linked[name], "serializer component manifest changed"
        report = json.loads(path.read_text())
        for flag in ("json_request_accepted", "full_query_accepted", "page_accepted"):
            assert report[flag] is False, "source inventory promoted execution acceptance"
        for source, expected in report.get("framework_read_sources", {}).items():
            assert digest((here / source).read_bytes()) == expected
        for source, expected in report.get("source_sha256", {}).items():
            assert digest((here / "source/discourse" / source).read_bytes()) == expected
        for change in report.get("guarded_changes", report.get("guarded_source_changes", [])):
            source = (here / "source/discourse" / change["source"]).read_bytes()
            assert digest(source[change["start_byte"]:change["end_byte"]]) == change["text_sha256"]
        outputs = report.get("candidates", report.get("candidate_source_sha256", {}))
        for source, expected in outputs.items():
            assert digest((here / "compat/discourse" / source).read_bytes()) == expected
            assert main["candidate_source_sha256"]["discourse/" + source] == expected
        if "framework_source" in report:
            source = (here.parent / report["framework_source"]).read_bytes()
            assert digest(source) == report["framework_sha256"]
            for span in report["copied_read_methods"]:
                assert digest(source[span["start_byte"]:span["end_byte"]]) == span["text_sha256"]
        reports[name] = report
    return reports
