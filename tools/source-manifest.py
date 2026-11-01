#!/usr/bin/env python3
"""Update source provenance deliberately; never run from a build or smoke test."""
import hashlib
import json
from pathlib import Path

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"


def source(path, origin="discourse", revision=PIN):
    root = Path("../discourse") if origin == "discourse" else Path("../run/bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47")
    return {"origin": origin, "revision": revision, "path": path,
            "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest()}


def entry(destinations, kind, paths, definitions, adaptations):
    return {"destinations": destinations, "kind": kind, "license": "GPL-2.0-or-later",
            "sources": [source(path) for path in paths],
            "selected_definitions": definitions, "adaptations": adaptations}


entries = [
    entry(["lib/serializers.rb"], "selective anonymous-scope adaptation", [
        "app/serializers/basic_topic_serializer.rb", "app/serializers/listable_topic_serializer.rb",
        "app/serializers/topic_list_item_serializer.rb", "app/serializers/topic_poster_serializer.rb",
        "app/models/topic_posters_summary.rb", "lib/pinned_check.rb", "config/locales/server.en.yml"],
        ["BasicTopicSerializer attributes", "ListableTopicSerializer#bumped/#seen/#unseen/#pinned/#unpinned/#include_excerpt?",
         "TopicListItemSerializer attributes/#last_poster_username", "TopicPostersSummary poster selection/descriptions/extras", "PinnedCheck anonymous branch", "English poster translations"],
        "ActiveModel serializers replaced with explicit JSON record projection. Only anonymous branches extracted; Ruby objects/UserLookup mapped to integer IDs and live PG records. No full serializer framework or I18n runtime."),
    entry(["lib/users.rb"], "selective anonymous-scope adaptation", [
        "app/models/user.rb", "app/models/user_avatar.rb", "app/models/optimized_image.rb",
        "lib/user_lookup.rb", "app/serializers/basic_user_serializer.rb", "app/serializers/poster_serializer.rb",
        "app/serializers/concerns/user_primary_group_mixin.rb", "app/serializers/concerns/user_flair_mixin.rb",
        "app/models/group.rb", "config/site_settings.yml"],
        ["User.avatar_template/system_avatar_template/letter_avatar_color/color_index", "UserAvatar.local_avatar_template/version", "OptimizedImage::VERSION", "UserLookup selected user/group columns", "BasicUserSerializer/PosterSerializer fields", "UserPrimaryGroupMixin/UserFlairMixin conditional attributes", "Group#flair_url selected icon/nil branches"],
        "JSON records instead of ActiveRecord. Task-site hostname localhost and root base-path, default small-logo path, optimized-image version 2 selected from pinned source defaults. Non-ASCII usernames, flair image uploads and unsupported avatar configurations fail closed; no image serving."),
    entry(["lib/latest.rb"], "runtime adapter and explicit SQL translation; NOT unchanged Discourse code", [
        "lib/topic_query.rb", "app/controllers/list_controller.rb", "app/models/topic.rb",
        "lib/guardian/topic_guardian.rb", "lib/guardian/category_guardian.rb", "lib/guardian.rb",
        "app/serializers/topic_list_serializer.rb", "app/models/topic_list.rb", "config/site_settings.yml",
        "plugins/discourse-solved/app/serializers/concerns/discourse_solved/topic_answer_mixin.rb",
        "plugins/discourse-solved/app/models/discourse_solved/solved_topic.rb",
        "plugins/discourse-solved/app/models/discourse_solved/topic_answer.rb",
        "plugins/discourse-topic-voting/plugin.rb", "plugins/discourse-topic-voting/lib/discourse_topic_voting/topic_extension.rb",
        "plugins/discourse-topic-voting/lib/discourse_topic_voting/category_extension.rb"],
        ["ListController latest no_definitions and pagination URL selection", "TopicQuery#list_latest/#latest_results/#default_results selected anonymous scopes", "TopicQuery#apply_ordering/#prioritize_pinned_topics/#remove_muted_categories/#apply_shared_drafts", "Topic listable/visible/deleted scopes and guardian public category policy", "TopicListSerializer list metadata and conditional fields", "Solved TopicAnswerMixin#has_accepted_answer/include_has_accepted_answer?", "Topic voting anonymous list can_vote/vote_count/user_voted fields"],
        "ActiveRecord scopes translated to parameterized PostgreSQL CTEs plus explicit JSON projection, 30-row default pagination. Reads run in read-only repeatable-read transactions. Settings defaults selected from source with explicit unsupported guards. No plugin registration/hook/modifier runtime; selected list attributes only. Tags/images/title generation and broader settings/options remain guarded or unextracted, see GAPS.md."),
    entry(["lib/letter_avatar_colors.rb"], "unchanged selected constant in renamed module", ["lib/letter_avatar.rb"],
        ["LetterAvatar::COLORS"], "Palette constant copied byte-for-byte; containing module renamed LetterAvatarColors. Image renderer not copied."),
    entry(["frontend/reference/application.html.erb"], "unchanged source reference only; NOT served", ["app/views/layouts/application.html.erb"],
        ["entire application layout"], "Byte-identical copy for next native bootstrap task; no Rails template engine is embedded."),
    entry(["frontend/application-shell.excerpt.html.erb", "frontend/INTEGRATION.md"], "selected source reference and integration contract; NOT served", [
        "app/views/layouts/application.html.erb", "lib/application_layout_preloader.rb", "app/helpers/application_helper.rb",
        "lib/topic_list_responder.rb", "frontend/discourse/app/lib/preload-store.js"],
        ["document setup/preload/mount hooks", "ApplicationLayoutPreloader common preload keys", "client_side_setup_data/preloaded_json", "TopicListResponder HTML/JSON selection", "populatePreloadStore"],
        "Selected excerpt explicitly omits most layout and is not a functional native template. Contract contains field names, not captured response/settings/session data."),
    entry(["frontend/build-ember-assets.sh"], "new isolated build adapter using actual Discourse frontend sources", [
        "frontend/discourse/rolldown.config.mjs", "frontend/discourse/package.json"],
        ["actual core Ember/Rolldown JS build"],
        "Stages source under build/, links installed dependencies, writes core JS/manifest only under build/assets/discourse. No Rails data backend, CSS/plugin/theme build or browser proof."),
]
emoji_paths = ["dist/emojis.json", "dist/aliases.json", "dist/tonable_emojis.json"]
entries.append({"destinations": ["data/emoji-unicode.json", "tools/carry-emoji.py", "data/discourse-emojis-attributions.md"],
                "kind": "source-data transformation, not Rails output", "license": "MIT package metadata; upstream artwork notices retained, no artwork copied",
                "sources": [source("app/models/emoji.rb")] + [source(path, "discourse-emojis", "1.0.47") for path in emoji_paths + ["attributions.md"]],
                "selected_definitions": ["Emoji.lookup_unicode/replacement_code and Unicode alias/tone data"],
                "adaptations": "Build-time Python transformation of packaged Unicode metadata. Runtime uses generated lookup; emoji deny-list policy is guarded unsupported. No image assets copied."})
pg_files = sorted(p for p in Path("vendor/pg").rglob("*") if p.is_file())
entries.append({"destinations": ["vendor/pg"], "kind": "unchanged vendored runtime dependency", "license": "MIT; vendor/pg/LICENSE",
                "origin": "https://github.com/roundhouse-rb/spinel-pg", "revision": "fe631b4ac4aba68168adf2ecce2c6c21006f7455", "version": "0.2.0",
                "adaptations": "Only runtime sources, package manifest and license carried; no source edits. Vendored because spin git ref accepts branches/tags rather than detached SHA.",
                "files": [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in pg_files]})
entries.append({"destinations": ["bin/discourse.rb", "tools/build.py", "test/", "reference/"],
                "kind": "new local runtime/build/verification adapters", "license": "GPL-2.0-or-later for this extraction",
                "adaptations": "Loopback TCP HTTP server over installed Spinel sockets; live pure-native PG client; no Ruby subprocess/proxy/canned response in serving path. Verification uses synchronous read-only Rails runner only, never a final data backend."})
manifest = {"schema_version": 1, "upstream": "Discourse", "original_revision": PIN,
            "upstream_license": "GPL-2.0-or-later; Copyright 2014-2026 Civilized Discourse Construction Kit, Inc. and contributors",
            "scope": "anonymous latest JSON at task-owned seeded site; browser and full plugin support NOT complete",
            "gaps": "GAPS.md", "plugin_coverage": "PLUGIN_SUPPORT.json", "entries": entries}
Path("SOURCE_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
