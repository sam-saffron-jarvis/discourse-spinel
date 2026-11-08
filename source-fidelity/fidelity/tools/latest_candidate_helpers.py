"""Install complete authorized shared read helpers into a separate candidate map."""
import json
import shutil

from verify import HERE, digest

HELPERS = ("lib/post_action_type_view.rb", "app/models/topic_poster.rb")


def materialize(app):
    manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
    original_map = app / "projection-map.json"
    originals = json.loads(original_map.read_text())
    candidate_map = app / "candidate-model-projections.json"
    candidates = json.loads(candidate_map.read_text()) if candidate_map.exists() else []
    for source_name in HELPERS:
        name = "discourse/" + source_name
        source = HERE / "compat" / name
        sha = digest(source.read_bytes())
        assert sha == manifest["candidate_source_sha256"][name]
        target = "app/models/" + source.name
        shutil.copyfile(source, app / target)
        originals = [item for item in originals if item["generated"] != target]
        candidates = [item for item in candidates if item["generated"] != target]
        candidates.append({"source_root": "compat/discourse", "source": source_name, "generated": target,
            "source_sha256": sha, "generated_sha256": sha,
            "selected_spans": [{"start_byte": 0, "end_byte": source.stat().st_size, "text_sha256": sha}],
            "limitation": "complete PATCHED read helper; see manifest's supported and unproved API/cache scope"})
    original_map.write_text(json.dumps(originals, indent=2) + "\n")
    candidate_map.write_text(json.dumps(candidates, indent=2) + "\n")
