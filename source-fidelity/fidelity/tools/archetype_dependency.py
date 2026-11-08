"""Complete genuine inputs for the measured registry205 Archetype dependency."""
import json
from pathlib import Path
import shutil


def materialize(here: Path, output: Path, digest, maps=None):
    maps = [] if maps is None else maps
    inputs = (
        ("discourse", "lib/archetype.rb", "app/models/archetype.rb"),
        ("framework", "activemodel-8.1.4/lib/active_model/serialization.rb", "app/models/active_model/serialization.rb"),
    )
    for root, original, generated in inputs:
        data = (here / "source" / root / original).read_bytes()
        destination = output / generated
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(here / "source" / root / original, destination)
        sha = digest(data)
        maps = [item for item in maps if item["generated"] != generated]
        maps.append({"source_root": root, "source": original, "generated": generated,
                     "source_sha256": sha, "generated_sha256": sha,
                     "selected_spans": [{"role": "complete_original_file", "start_byte": 0,
                                         "end_byte": len(data), "text_sha256": sha}],
                     "limitation": "complete original Archetype + genuine source serialization mixin; not plugin activation/settings/query proof"})
    (output / "projection-map.json").write_text(json.dumps(maps, indent=2) + "\n")
    return maps
