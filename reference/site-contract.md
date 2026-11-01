# Ticket 007 anonymous site/settings reference adapter

`native_site.rb` is an explicit native-runtime adapter, not copied Rails code. API:

- `NativeReference.site_json(pg_connection)` returns an anonymous Site bootstrap subset as a JSON string.
- `NativeReference.client_settings_json(pg_connection)` returns JSON for only the explicit client-safe allowlist. It reads live overrides with a parameterized SELECT; unlisted rows (including secrets) are ignored. Callers must use a read-only PG transaction (the native process sets the connection read-only).
- `NativeReference.read_client_settings(pg_connection)` returns the corresponding parsed hash for internal use.

Source pin: Discourse `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. SHA-256 values below are of those pinned checkout files; they are source provenance, not response captures.

| Source | SHA-256 | Extracted definitions |
|---|---|---|
| `app/models/site.rb` | `77e404c42b30329ce3c05f06e46110afaddf4380062b3f8670298c7bbb08d427` | `Site.json_for(guardian)` anonymous branch and normal serializer path |
| `app/serializers/site_serializer.rb` | `f734b1b158118654bee273478d696b0a11b6350b58f36c3dbbe76a5544ebe927` | Site field names / relationships; categories, archetypes, notification/post/trust fields |
| `lib/site_setting_extension.rb` | `7f4e727c17ef9a4da8254e5ee70ea272dd886dbf88b0936a4ee37f435b6aaeab` | `client_settings` initialization and `client_settings_hash_uncached` behavior |
| `app/models/site_setting.rb` | `a44e4bf6277b8693ae59f63dcabca0b4fbf474f3a80e6a10f6ef6db682d86986` | explicitly added client settings (`default_locale`, locale helpers and logo URLs) |
| `config/site_settings.yml` | `f5d22ff1dc5e7afc1d5c136d0160c12443639a1df792ed43553460252db1e3d1` | client flags, defaults and setting declarations |
| `app/models/notification.rb` | `ecd70b08f9c48bb87754daeb425788360103a20a2fdbe01e190701ff13ebe1d6` | `Notification.types` enum |
| `app/models/post.rb` | `83ddbfe431d831eb6e05b00d87a3ebed1be91560544d17159c8835119db9912f` | `Post.types` enum |
| `lib/trust_level.rb` | `b2cae9d0a789fed04c50eea7b68669056b248d92d6a5e4a7230722054fdca657` | trust-level enum |
| `config/locales/server.en.yml` | `13fdf75fb404c3da601f7605d7f8e307f87676774e30c6bb199ecbcd62d46af9` | English archetype names |
| `plugins/discourse-topic-voting/plugin.rb` | `b602db8812683e9d7a4375922381407ab383ccca6df29385d283458611f758ad` | Appended `votes` to core/anonymous filters and menu fields |

The `client-settings-contract.json` is generated (not captured) with `ruby reference/generate-client-settings.rb` from the pinned `config/site_settings.yml`. It contains source defaults, types, client flags and upcoming-change metadata for the 390 non-themeable, non-secret core `client: true` settings. `NativeReference` applies the source-declared promoted defaults (including `top_menu` → `latest|new|hot|categories`) and direct DB overrides; the promotion threshold uses the source default `beta` unless
its explicitly queried internal setting is overridden. The threshold is never exported
in client settings. It includes browser settings such as `avatar_sizes`, `anon_polling_interval`, `background_polling_interval`, and navigation values. It does not include live DB output. The generator checks the Discourse revision and embeds the YAML SHA-256. Computed Ruby helpers and plugin settings are outside this source catalog.

## Read-only oracle

From the minimal directory, source `../harness/env.sh`, then:

```sh
cd ../discourse
DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development' \
REDIS_URL='redis://127.0.0.1:6399/0' RAILS_ENV=development \
bundle exec bin/rails runner ../minimal/reference/site-oracle.rb
```

The runner checks both the exact `Site.json_for(Guardian.new)` aggregate API and, after isolating its error in a savepoint, directly calls the actual `SiteSerializer`/`Site` field methods to compare every native scalar/enum/list/menu/permission field. The `categories` field is compared as an ordered ID set plus exact values for every native-emitted category key; actual category fields omitted by the narrow projection are named and counted. `SiteSetting.client_settings_json` completes under the read-only transaction and is compared against all 390 generated core `client: true` settings. Additional Rails client setting keys from plugins/computed helpers are counted as omitted; full-catalog parity remains false by design. The oracle exits successfully only when the bounded source-core setting subset and every emitted Site/category field match. It prints no settings values or response bodies.


The source-core client-settings comparison is currently exact across 390/390 keys for this DB. It does not claim full Rails client-catalog parity: the oracle reports 375 additional plugin/computed keys (full-catalog parity false). Upcoming-change promotion honors the live internal `promote_upcoming_changes_on_status` setting (source default `beta`); plugin-owned upcoming-change dependencies remain unsupported. Nonempty uploaded-image lists fail closed instead of returning a wrongly typed client value. Non-English site preloads fail closed.

 `Site.json_for` calls `SiteSerializer#include_wizard_required?` → `Wizard.user_requires_completion?` → `Wizard#requires_completion?`; the topic-count branch assigns `SiteSetting.bypass_wizard_check = true`, which reaches `SiteSettingExtension#add_override!` and `SiteSettings::DbProvider#save` (`lib/site_settings/db_provider.rb:38`). PostgreSQL rejects that `INSERT` under `SET TRANSACTION READ ONLY`; the oracle catches it in a rolled-back savepoint and retains the exact source frames. It then compares the actual field methods independently, without invoking or stubbing the write. The separate full `SiteSetting.client_settings_json` API succeeds read-only. Do not relax the read-only guard or suppress the writer.


This is not a complete `SiteSerializer` implementation. Category records are a deliberately narrow public projection, not full `SiteCategorySerializer` output. The oracle explicitly reports the actual serializer field names not represented here (for example category notification level/permissions, topic URL/counts, descriptions, upload relations and display options), and compares every emitted field value and ordering. Category guardians/callbacks/localization, group/category permissions, sidebar sections, groups, theme/color schemes, user fields, auth providers, tag lists, flags/action rows, site URLs, access-control, CSP/security settings and plugin/theme modifiers remain unsupported. Archetype names are the pinned English translations; non-English default locales fail closed. Permission fields currently reflect source defaults (anonymous search allowed, anonymous tag creation/tagging denied); dynamic non-client permission settings or plugin/guardian overrides are an explicit gap and cause oracle mismatches rather than being silently accepted. Notification types are the pinned core enum only and do not imply plugin type support.

The native Site projection now also emits `hashtag_icons`. It follows the pinned `HashtagAutocompleteService.data_source_icon_map` registry for selected sources: core `CategoryHashtagDataSource` is always enabled (`category` → `folder`), core `TagHashtagDataSource` is conditional on live `tagging_enabled` (`tag` → `tag`), and the task's installed Chat plugin source `Chat::ChannelHashtagDataSource` is conditional on live `enable_public_channels` (`channel` → `comment`, plugin setting's source default is true when no DB override exists). Provenance files are `app/services/hashtag_autocomplete_service.rb`, `app/services/category_hashtag_data_source.rb`, `app/services/tag_hashtag_data_source.rb`, `plugins/chat/lib/chat/channel_hashtag_data_source.rb`, and `plugins/chat/config/settings.yml`; setting values are read from `site_settings` with bound SELECTs (the core one via the safe client allowlist). Arbitrary plugin-registered `DiscoursePluginRegistry.hashtag_autocomplete_data_sources` remain unsupported. Actual `SiteSerializer#hashtag_icons` is included in `site-oracle.rb`; any unmodeled registry entry is reported as mismatch, not filtered away.
