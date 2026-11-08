"""Pinned supporting source for the partial latest-method measurement.

Complete helper files only; no runtime values, fake models or permission stubs.
Existing immutable copies are checked, never overwritten. Additional originals
are copied once from the exact pinned Git blobs and appended to the source lock.
"""
import json
import subprocess

from verify import HERE, ROOT, PIN, digest

HELPERS = (
    "app/models/concerns/has_custom_fields.rb", "app/models/topic_list.rb", "app/models/topic_poster.rb", "app/models/topic_posters_summary.rb",
    "lib/user_lookup.rb", "lib/group_lookup.rb", "lib/notification_levels.rb", "lib/enum.rb",
    "lib/post_action_type_view.rb", "lib/flag_settings.rb",
)


MODELS = ("User", "Group", "Tag", "TopicTag", "SharedDraft", "TopicUser", "CategoryUser", "TagUser",
          "DismissedTopicUser", "PostAction", "PostActionType", "Post", "Flag", "TagGroup", "TagGroupMembership",
          "TagGroupPermission", "BaseTimer", "TopicTimer", "TopicCustomField")


SERVICES = ("lib/discourse_plugin_registry.rb", "lib/topics_filter.rb", "lib/search.rb", "lib/discourse_tagging.rb",
            "app/models/global_setting.rb", "lib/discourse.rb")


def materialize(app, read_models=False, services=False, fresh_flag_reads=False):
    lock_path = HERE / "SOURCE_LOCK.json"
    lock = json.loads(lock_path.read_text())
    assert lock["discourse_revision"] == PIN
    locked = {item["path"]: item["sha256"] for item in lock["files"]}
    maps_path = app / "projection-map.json"
    maps = json.loads(maps_path.read_text())
    import re
    paths = list(HELPERS)
    if services:
        paths += list(SERVICES)
        if not fresh_flag_reads:
            paths.append("lib/cache.rb")
    if read_models:
        paths += ["app/models/" + re.sub(r"([a-z\d])([A-Z])", r"\1_\2", name).lower() + ".rb" for name in MODELS]
    for name in paths:
        original = subprocess.check_output(["git", "-C", ROOT / "discourse", "show", f"{PIN}:{name}"])
        assert (ROOT / "discourse" / name).read_bytes() == original
        sha = digest(original)
        copied = HERE / "source/discourse" / name
        if name in locked:
            assert locked[name] == sha
            assert copied.read_bytes() == original
        else:
            if copied.exists():
                assert copied.read_bytes() == original
            else:
                copied.parent.mkdir(parents=True, exist_ok=True)
                copied.write_bytes(original)
            lock["files"].append({"path": name, "sha256": sha})
        destination = "app/models/" + name.rsplit("/", 1)[-1]
        (app / destination).write_bytes(original)
        maps = [item for item in maps if item["generated"] != destination]
        maps.append({"source": name, "generated": destination, "source_sha256": sha, "generated_sha256": sha,
            "selected_spans": [{"start_byte": 0, "end_byte": len(original), "text_sha256": sha, "role": "complete_original_helper"}],
            "limitation": "complete pinned helper input ONLY; dependency closure not yet executable/admitted"})
    # This complete original concern is already locked/verified against the
    # cached activemodel gem. Do not invent an empty module to resolve includes.
    from framework_sources import verify_framework_sources
    verify_framework_sources(lock, HERE, ROOT, digest)
    group = next(item for item in lock["framework_sources"] if item["gem"] == "activemodel")
    item = next(item for item in group["files"] if item["package_member"] == "lib/active_model/serialization.rb")
    original = (HERE / item["path"]).read_bytes()
    sha = digest(original)
    assert sha == item["sha256"]
    destination = "app/models/active_model_serialization.rb"
    (app / destination).write_bytes(original)
    maps = [entry for entry in maps if entry["generated"] != destination]
    maps.append({"source_root": "framework", "source": item["path"].removeprefix("source/framework/"),
        "generated": destination, "source_sha256": sha, "generated_sha256": sha,
        "selected_spans": [{"start_byte": 0, "end_byte": len(original), "text_sha256": sha, "role": "complete_original_framework_concern"}],
        "limitation": "complete original concern; no native dispatch or serialization admission inferred"})
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    maps_path.write_text(json.dumps(maps, indent=2) + "\n")
    return maps
