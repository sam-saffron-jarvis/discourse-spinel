#!/usr/bin/env python3
"""Update source provenance deliberately; never run from a build or smoke test."""
import hashlib
import json
from pathlib import Path

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"


def source(path, origin="discourse", revision=PIN):
    roots = {
        "discourse": Path("../discourse"),
        "discourse-emojis": Path("../run/bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47"),
        "message_bus": Path("../run/bundle/ruby/4.0.0/gems/message_bus-5.0.0"),
        "discourse-fonts": Path("../run/bundle/ruby/4.0.0/gems/discourse-fonts-0.0.19"),
    }
    root = roots[origin]
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
    entry(["lib/topic.rb", "reference/capture-topic-rails.rb", "reference/topic-contract.md"],
        "bounded anonymous TopicView/serializer SQL and JSON-record adaptation; not unchanged Rails", [
            "lib/topic_view.rb", "app/controllers/topics_controller.rb", "config/routes.rb",
            "app/models/topic.rb", "app/models/post.rb", "app/models/draft_sequence.rb",
            "lib/guardian/topic_guardian.rb", "lib/guardian/category_guardian.rb", "lib/guardian/post_guardian.rb",
            "app/serializers/topic_view_serializer.rb", "app/serializers/topic_view_details_serializer.rb",
            "app/serializers/post_stream_serializer_mixin.rb", "app/serializers/basic_post_serializer.rb",
            "app/serializers/post_serializer.rb", "app/serializers/basic_user_serializer.rb",
            "lib/pinned_check.rb", "config/locales/server.en.yml"],
        ["TopicView authorization/visible post types/sort_order/20-post and near-post windows",
         "TopicViewSerializer selected anonymous scalar getters", "PostStreamSerializerMixin stream/posts",
         "BasicPostSerializer hidden cooked placeholder", "PostSerializer selected anonymous getters",
         "TopicViewDetailsSerializer limited details/basic users", "source slug/numeric/post-number routes"],
        "Bound SELECTs over live task PG in repeatable-read read-only transactions. Public-category Guardian policy denies absent categories, restricted/private/deleted/shared-draft topics, permits direct unlisted links. Deleted posts/whispers omitted, hidden cooked redacted by SQL to the source English placeholder, never raw. All emitted root response keys/values/order compared to fresh actual source getters, not full serializer parity. No writes/visits/view-counter acknowledgement, arbitrary filters, plugin hooks, post-ID window endpoint, mega streams, title cooking, tags or images. See exact contract and gaps."),
    entry(["lib/surface.rb", "frontend/native_document.rb"], "mounted topic deployment adaptation and native topic document", [
            "lib/pretty_text.rb", "config/discourse_defaults.conf", "app/controllers/topics_controller.rb",
            "frontend/discourse/app/models/topic.ts", "frontend/discourse/app/routes/topic/from-params.js"],
        ["PrettyText.paths baseUri cook-time deployment context", "topic_<id> preload and Ember loadTopicView",
         "topic document title and canonical metadata"],
        "Unmodified Ember renders source-backed posts. Root cooked bytes match actual source; configured widget-prefix response copies relocate quoted local src/href/poster attributes to the mount without rebaking stored posts. This explicit mount-only divergence is not counted as root Rails serializer byte parity. External/protocol-relative/fragment URLs unchanged."),
    entry(["reference/native_site.rb"], "selected source hashtag registry/icons for actual cooked decorators", [
            "app/serializers/site_serializer.rb", "app/services/hashtag_autocomplete_service.rb",
            "app/services/category_hashtag_data_source.rb", "app/services/tag_hashtag_data_source.rb",
            "plugins/chat/lib/chat/channel_hashtag_data_source.rb", "plugins/chat/config/settings.yml"],
        ["SiteSerializer#hashtag_icons", "HashtagAutocompleteService.data_source_icon_map",
         "category/tag/Chat channel source icons and enable predicates"],
        "Selected source constants plus live tagging_enabled/enable_public_channels SELECTs, with exact actual getter comparison. No arbitrary plugin registry or Chat routes/runtime support."),
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
    entry(["reference/native_site.rb", "reference/client-settings-contract.json", "reference/generate-client-settings.rb"],
        "bounded anonymous Site/client-safe settings adaptation; not full serializer parity", [
            "app/models/site.rb", "app/serializers/site_serializer.rb", "app/serializers/site_category_serializer.rb",
            "lib/site_setting_extension.rb", "lib/upcoming_changes.rb", "app/models/site_setting.rb", "config/site_settings.yml",
            "app/models/notification.rb", "app/models/post.rb", "lib/trust_level.rb", "lib/archetype.rb",
            "config/locales/server.en.yml", "lib/discourse.rb", "plugins/discourse-topic-voting/plugin.rb"],
        ["Site.json_for anonymous serializer fields", "source client:true catalog defaults/types and bound live overrides",
         "English archetype/notification/post/trust enums", "public category projection", "core/voting navigation constants"],
        "Source YAML generates a safe bounded catalog, never DB/preload captures. Live selected overrides and upload URLs are read natively. Every emitted field is compared to actual read-only Rails getters; aggregate Site.json_for write-on-read wizard blocker and all omitted fields remain reported. Non-English/login-required site unsupported. No full Guardian/plugin/theme runtime."),
    entry(["lib/preloads.rb", "lib/valkey.rb"], "selected guest common preloads and read-only task Valkey adapter", [
        "lib/application_layout_preloader.rb", "lib/read_only_mixin.rb", "lib/discourse.rb", "lib/discourse_redis.rb",
        "app/models/topic.rb", "app/models/post.rb", "app/models/concerns/trashable.rb", "app/models/custom_emoji.rb"],
        ["ApplicationLayoutPreloader common keys", "Topic#banner guest category guard", "Discourse read-only flags and logical current_db namespace"],
        "Live public banner/site/settings/topic_list and read-only mode keys. Valkey RESP reads use task DB0/logical site default. Theme overrides/custom HTML/activated themes/upcoming changes omitted explicitly; custom emoji fails closed when nonempty. Latest and common preload read transactions are separate."),
    entry(["frontend/native_document.rb", "frontend/stage-assets.py"], "actual core document/bootstrap and isolated source-asset adaptation", [
        "app/views/layouts/application.html.erb", "app/views/layouts/_head.html.erb", "app/helpers/application_helper.rb", "lib/ember_assets.rb",
        "lib/js_locale_helper.rb", "config/locales/client.en.yml", "config/locales/server.en.yml",
        "lib/svg_sprite.rb", "app/controllers/svg_sprite_controller.rb", "app/views/static/service-worker.js.erb",
        "frontend/discourse/scripts/js/browser-detect.js", "frontend/discourse/scripts/js/browser-update.js",
        "lib/stylesheet/compiler.rb", "lib/stylesheet/importer.rb", "app/assets/stylesheets/color_definitions.scss"],
        ["real setup/config/import-map/modulepreload/mount layout", "English locale/moment formatter contract", "core SVG symbols",
         "core service worker", "actual stylesheets and public image assets"],
        "Existing core Rolldown outputs reused without JS edits. Common CSS is byte-hashed reference cache output (not independently reproduced), with local root/reference-host image URLs rebased relative to the staged stylesheet; stage descriptor records separate source/output hashes. Native document escapes attributes and script JSON, prefixes static/module/link routes. English core locale only; compiled MessageFormat/plugin/theme translations and plugin worker hooks remain explicit gaps. Other stage artifacts and source hashes are recorded in ignored build/assets/native/manifest.json, not captured Rails preloads."),
    entry(["lib/avatars.rb", "tools/stage-media.py"], "selected public avatar adapter and source asset staging", [
        "app/controllers/user_avatars_controller.rb", "app/models/user_avatar.rb", "app/models/optimized_image.rb"],
        ["UserAvatarsController#show_in_site/#render_blank", "current uploaded avatar membership and optimized image lookup"],
        "Stages actual current-public avatar bytes into private build/media; serving checks live username/current-upload/secure flag, canonical path and realpath containment. Existing optimized size preferred; original image fallback omits resizing. External letter-avatar CDN prohibited: explicitly uses actual source blank-avatar fallback rather than fabricating identities. Historical/associated avatars not implemented."),
]
entries.append({"destinations": ["lib/message_bus.rb", "vendor/message_bus/LICENSE"],
                "kind": "native read-only short-poll adaptation of MessageBus 5.0.0", "license": "MIT; vendor/message_bus/LICENSE",
                "sources": [source(p, "message_bus", "5.0.0") for p in ["lib/message_bus.rb", "lib/message_bus/client.rb", "lib/message_bus/message.rb", "lib/message_bus/backends/redis.rb", "lib/message_bus/rack/middleware.rb", "LICENSE"]] +
                           [source("config/initializers/004-message_bus.rb"), source("app/models/group.rb"), source("app/models/post.rb"), source("app/models/topic.rb")],
                "selected_definitions": ["Client#backlog/#allowed?", "Redis last_ids/backlog storage", "Message transport codec", "Rack backlog_to_json and synchronous branch", "Discourse logical site/anonymous group selection"],
                "adaptations": "Bounded observed guest latest and live-authorized public /topic/:id channels only; live Valkey MGET/ZRANGEBYSCORE and source user/group/client ACL filtering. Native topic channels recheck live topic Guardian SQL before reading backlog. No canned empty poll body. Native pure tests plus exact live comparison at four positions to actual MessageBus including three real topic channels. No long-poll/chunking, publish, authenticated identity, arbitrary/plugin channels or listeners."})
emoji_paths = ["dist/emojis.json", "dist/aliases.json", "dist/tonable_emojis.json"]
entries.append({"destinations": ["data/emoji-unicode.json", "tools/carry-emoji.py", "data/discourse-emojis-attributions.md"],
                "kind": "source-data transformation, not Rails output", "license": "MIT package metadata; upstream artwork notices retained, no artwork copied",
                "sources": [source("app/models/emoji.rb")] + [source(path, "discourse-emojis", "1.0.47") for path in emoji_paths + ["attributions.md"]],
                "selected_definitions": ["Emoji.lookup_unicode/replacement_code and Unicode alias/tone data"],
                "adaptations": "Build-time Python transformation of packaged Unicode metadata. Runtime uses generated lookup; emoji deny-list policy is guarded unsupported. No image assets copied."})
entries.append({"destinations": ["build/assets/native/images/emoji/twitter/", "build/assets/native/css/fonts/"],
                "kind": "unchanged installed package artwork/font build assets; ignored outputs only",
                "license": "Original packaged artwork/font licensing; emoji attributions in data/discourse-emojis-attributions.md; original font bytes retain embedded notices",
                "sources": [source(p, "discourse-emojis", "1.0.47") for p in ["attributions.md", "dist/emoji/twemoji/wave.png", "dist/emoji/twemoji/speaking_head.png"]] +
                           [source(p, "discourse-fonts", "0.0.19") for p in ["lib/discourse_fonts.rb", "vendor/assets/fonts/InterVariable.woff2", "vendor/assets/fonts/JetBrainsMono-Regular.woff2", "vendor/assets/fonts/JetBrainsMono-Bold.woff2"]],
                "adaptations": "No artwork/font byte edits. Stage manifest records all Twemoji source/output paths and hashes, not only these observed emoji requests; twitter is the legacy public alias for twemoji. Palette font URLs rebased relative to CSS so root and widget prefix use the same bytes. No remote font/avatar/CDN request."})
pg_files = sorted(p for p in Path("vendor/pg").rglob("*") if p.is_file())
entries.append({"destinations": ["vendor/pg"], "kind": "unchanged vendored runtime dependency", "license": "MIT; vendor/pg/LICENSE",
                "origin": "https://github.com/roundhouse-rb/spinel-pg", "revision": "fe631b4ac4aba68168adf2ecce2c6c21006f7455", "version": "0.2.0",
                "adaptations": "Only runtime sources, package manifest and license carried; no source edits. Vendored because spin git ref accepts branches/tags rather than detached SHA.",
                "files": [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in pg_files]})
entries.append({"destinations": ["bin/discourse.rb", "lib/mini_profiler.rb", "tools/build.py", "test/", "reference/"],
                "kind": "new local runtime/build/verification adapters", "license": "GPL-2.0-or-later for this extraction",
                "adaptations": "Loopback TCP HTTP server over installed Spinel sockets; live pure-native PG client; no Ruby subprocess/proxy/canned response in serving path. Verification uses synchronous read-only Rails runner only, never a final data backend. Optional request-local MiniProfiler integration uses the separately hash-verified MIT native port/client under vendor/rack-mini-profiler/MANIFEST.json; canonical numeric topic names exclude user slugs, bindings and query strings."})
manifest = {"schema_version": 1, "upstream": "Discourse", "original_revision": PIN,
            "upstream_license": "GPL-2.0-or-later; Copyright 2014-2026 Civilized Discourse Construction Kit, Inc. and contributors",
            "scope": "anonymous latest JSON and bounded anonymous topic JSON/content with actual core Ember browser rendering at task-owned site; no full serializer/plugin/auth parity",
            "gaps": "GAPS.md", "plugin_coverage": "PLUGIN_SUPPORT.json", "entries": entries}
Path("SOURCE_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
