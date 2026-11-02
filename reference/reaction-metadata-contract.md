# Native anonymous topic reaction metadata contract

Scope: native anonymous topic serialization only. This implements the source plugin's
`TopicView.on_preload`/`:post` and `:topic_view` serializer additions when
`discourse_reactions_enabled` is true. It does not claim broader plugin support or
replace either reactions-users endpoint.

## Pinned source basis

Source checkout: `../discourse`, SHA `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`.
The behavior is taken from:

- `plugins/discourse-reactions/plugin.rb`: enabled-only `TopicView.on_preload`,
  `:reactions`, `:current_user_reaction`, `:reaction_users_count`,
  `:current_user_used_main_reaction`, and topic-view `:valid_reactions`.
- `lib/discourse_reactions/reactions_serializer_helpers.rb`:
  `preload_post_reactions`, `current_user_reaction_for_post`,
  `reaction_users_count_for_post`, and `current_user_used_main_reaction_for_post`.
- `lib/discourse_reactions/topic_view_serializer_extension.rb`:
  `posts_reaction_users_count` (the preload count query).
- `lib/discourse_reactions/post_extension.rb` and core `app/models/emoji.rb`:
  `Post#emoji_reactions` and `Emoji.exists?` behavior.
- `app/models/discourse_reactions/reaction.rb`: `valid_reactions`,
  `reactions_counting_as_like`, main reaction and exclusions.

The helper's PostgreSQL reads model these exact source operations:

1. **Stored emoji reactions**: source `Post#emoji_reactions` first calls
   `Emoji.exists?(reaction_value)`, then the helper selects positive stored counts
   (`reaction_users_count.to_i > 0`). Native SQL reads all selected-post definitions
   so malformed values fail before the counter filter, matching the source order.
   `NativeEmoji.reaction_exists?` applies the source cold lookup, rejects ambiguous
   cache-sensitive non-tonable tone variants, and does not filter by enum type.
   A valid positive emoji with an unsupported enum type fails closed.
   Source emoji existence is standard data plus source aliases/tonability. Custom
   emoji are an explicit unsupported boundary: a read-only `custom_emojis` count
   must be zero. Unknown historical values are omitted from the displayed
   reactions, while their reaction-user rows still participate in the distinct
   preload user count and source like suppression. Stored counters are not
   recounted from reaction users; disabled-but-existing standard emoji remain
   displayable.
2. **Like merge**: copy of the helper `likes_count` SQL: non-deleted type-2
   `post_actions`, excluding actors with a non-main/non-excluded reaction and
   excluding actors with a main reaction. Positive likes merge into main-reaction
   reaction-user count; output sorts by descending count then reaction ID. It is
   deliberately distinct from either reactions-users controller query.
3. **Preloaded count**: copy of
   `TopicViewSerializer.posts_reaction_users_count`: `UNION ALL` non-deleted type-2
   likes with reaction-user rows, then `COUNT(DISTINCT user_id)` per post. This
   count does not apply the display merge's shadow-like exclusions.
4. Anonymous helpers return `current_user_reaction: null` and
   `current_user_used_main_reaction: false` (`scope.is_anonymous?`). `valid_reactions`
   is the source Set order: main reaction followed by configured enabled reactions,
   deduplicated. Missing site-setting rows use the actual plugin defaults (plugin
   enabled by default; the upstream excluded-from-like list copied from
   `config/settings.yml`), not an empty/disabled fallback.

The SQL constants in `lib/reaction_metadata.rb` are read-only SQL transcriptions of
those source operations. Emoji filtering calls `NativeEmoji.exists?`, whose
standard/alias/tonability catalog is pinned to the source emoji data. It mirrors the
cold source predicate; the source's deferred cache is keyed by name rather than tone,
so warm cache order effects are not emulated. The native preload fails closed when the
task DB has custom emoji rows, rather than silently omitting them. `test/reaction_metadata.rb`
exercises typed PostgreSQL CTE shadows; records are synthetic fixture data and are not
live DB reaction records. It covers a disabled-but-valid historical emoji, an invalid
emoji whose user still counts, positive/nonpositive stored counts, an unsupported valid
emoji enum type, and the custom-emoji boundary.

`test/reaction_metadata_source.rb` is the actual upstream source oracle. It invokes
`ReactionsSerializerHelpers.preload_post_reactions`, anonymous helper methods,
`PostReactionsQuery`, and the actual controller `format_user` against the same
fixture CTEs and compares exact results with native-generated artifacts. Its only
cache substitution is test-only transport: source `Emoji.find_emoji` still executes
the original cache block, but an in-process hash implements `defer_get_set`; source
`Emoji.load_standard`/`load_custom` remain the data producers. It does not write to
Valkey or provide canned emoji results.

## Output and boundaries

When the plugin setting is enabled, topic JSON includes post reaction metadata on
serialized posts from the selected post window only (the source TopicView preload
receives `topic_view.posts`, not the full stream), and top-level `valid_reactions`.
When disabled, all five plugin fields are omitted; no fabricated null/false
placeholders are emitted. The only implemented user context is anonymous, with no
ignored users. Reaction rows and like actions are read only. Existing topic and
reactions endpoints are unchanged.

This helper does not load reaction-user associations or per-user can-undo data,
render authenticated fields, apply user ignores, add UI behavior, or implement
writes. Positive synthetic fixture evidence must remain labeled synthetic and
separate from live parity evidence.

## Test

The native metadata and browser tests compile their fixtures to the native executable;
they require the task PG identity and are synthetic/read-only:

```sh
source ../harness/env.sh
DATABASE_URL=postgres://discourse@127.0.0.1:5499/discourse_development spin test test/reaction_metadata.rb
DATABASE_URL=postgres://discourse@127.0.0.1:5499/discourse_development spin test test/reaction_metadata_browser.rb
```

The browser artifact is `build/reaction-browser-fixtures-native.json`. It contains
65 distinct named ASCII actors: 40 clap and 25 heart, metadata `reaction_users_count`
65, and actual native `NativeReactions.call` responses for the all-reactions pages
0–2, clap pages 0–1, and heart page 0. Every endpoint entry includes exact path,
filter, page, limit, status, and JSON body. Its embedded `source_tables` are synthetic
fixture input, not live data. The parent browser test must use a URL-rewritten fixture
post ID while keeping the live post model identity separate; these responses are
explicitly mocked fixture transport, not a live endpoint claim.

The source oracle verifies both native fixtures with actual upstream plugin helpers,
query and serializer under read-only CTE shadows:

```sh
source ../harness/env.sh
export DATABASE_URL=postgres://discourse@127.0.0.1:5499/discourse_development
export REDIS_URL=redis://127.0.0.1:6399/0
export PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000'
cd ../discourse
bin/rails runner ../minimal/test/reaction_metadata_source.rb
```

This creates `build/reaction-browser-fixtures-source.json`. The source oracle uses
fresh local deferred-cache adapters, so source Emoji lookup executes cold canonical
standard emoji probes without writes to Valkey. Existing topic source-parity assertions
are owned by the parent integration lane and were not modified here.
