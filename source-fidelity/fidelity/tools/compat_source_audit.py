"""Separate candidate-projection audit; never relax the immutable-source audit."""
import json
from pathlib import Path

from verify import HERE, digest


def audit(app):
    path = app / "candidate-model-projections.json"
    if not path.exists():
        return []
    manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
    entries = json.loads(path.read_text())
    for item in entries:
        assert item["source_root"] == "compat/discourse"
        relative = Path(item["source"])
        assert not relative.is_absolute() and ".." not in relative.parts
        expected_output = str(relative) if relative.parts[0] == "app" else "app/models/" + relative.name
        assert item["generated"] == expected_output
        name = "discourse/" + item["source"]
        source = (HERE / "compat" / name).read_bytes()
        assert digest(source) == manifest["candidate_source_sha256"][name] == item["source_sha256"]
        output = (app / item["generated"]).read_bytes()
        assert digest(output) == item["generated_sha256"]
        assert len(source) == len(output)
        selected = bytearray(len(source))
        for span in item["selected_spans"]:
            start, end = span["start_byte"], span["end_byte"]
            assert output[start:end] == source[start:end]
            assert digest(source[start:end]) == span["text_sha256"]
            selected[start:end] = b"1" * (end - start)
        assert all(selected[index] or byte in (10, 32) for index, byte in enumerate(output))
    return entries
