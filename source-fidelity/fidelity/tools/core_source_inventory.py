"""Acquire complete pinned CORE files observed by the no-plugin reference.

This is a source inventory, not a closed-world proof: unobserved branches still
exist in each complete file and must be implemented/refused, never silently
trimmed using an observed production value or a recorded response.
"""
import json
from pathlib import Path
import subprocess

from verify import HERE, ROOT, PIN, digest


def acquire(evidence_path):
    evidence_path = Path(evidence_path)
    evidence = json.loads(evidence_path.read_text())
    profile = evidence["actual_no_plugin_boot"]
    assert profile["load_plugins_env"] == "0" and profile["load_plugins"] is False
    assert not any(profile[key] for key in ("plugin_instance_names", "compiled_plugin_sources", "loaded_plugin_sources"))
    observed = evidence["original_core_query_reference"]["original_core_calls"][:]
    http = evidence.get("original_core_http_reference", {}).get("requests", {})
    for request in http.values():
        observed.extend(request.get("original_core_calls", []))
    sources = sorted({item["source"] for item in observed})
    assert sources and all(not path.startswith("plugins/") for path in sources)
    lock_path = HERE / "SOURCE_LOCK.json"
    lock = json.loads(lock_path.read_text())
    assert lock["discourse_revision"] == PIN
    existing = {item["path"]: item["sha256"] for item in lock["files"]}
    manifest = []
    for source in sources:
        relative = Path(source)
        assert not relative.is_absolute() and ".." not in relative.parts
        original = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:{source}"])
        assert (ROOT / "discourse" / source).read_bytes() == original
        sha = digest(original)
        if source in existing:
            assert existing[source] == sha
        else:
            destination = HERE / "source/discourse" / source
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(original)
            lock["files"].append({"path": source, "sha256": sha})
        assert (HERE / "source/discourse" / source).read_bytes() == original
        manifest.append({"source": source, "sha256": sha, "bytes": len(original), "complete_original": True,
                         "observed_methods": [item for item in observed if item["source"] == source]})
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    report = {"profile": "original-core-no-plugins", "source_revision": PIN,
              "reference_evidence": str(evidence_path), "reference_sha256": digest(evidence_path.read_bytes()),
              "scope": "observed complete core source resources ONLY; NOT a closed-world/native query/page proof",
              "production_values_used_as_native_inputs": False, "files": manifest}
    output = evidence_path.parent / "core-source-inventory.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    import sys
    report = acquire(sys.argv[1])
    print(f"Acquired {len(report['files'])} complete pinned core files; inventory ONLY")
