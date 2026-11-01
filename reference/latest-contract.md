# `/latest` Rails reference contract (anonymous)

Status: source-derived reference for Ticket004, not a runtime implementation or response fixture. Do not serve files under this directory. The capture script runs a read-only Rails oracle; the probe compares its recorded JSON with the live native endpoint.

## Provenance

Reference checkout: `discourse/` at `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8` (the pin in `minimal/README.md`). Source hashes below identify the inspected files at that checkout.

| Path | SHA-256 |
|---|---|
| `app/controllers/list_controller.rb` | `dbced8e36813d9d6221cb6316b48e1e3eb4ad70ecdec58f319f9569ba5f9edc0` |
| `lib/topic_query.rb` | `9066840709436451bd392921f1dfaeed121ce0024e63916bb0e388145f8762dc` |
| `lib/topic_list_responder.rb` | `aa029946c01a1cd803504af21e9960f2d259482f67656b4a6d151da3e985704b` |
| `app/serializers/topic_list_serializer.rb` | `c3d062421d91095c0f378de047693de500192ca3dc4b3f94a4f8b6a764f4cbc4` |
| `app/serializers/topic_list_item_serializer.rb` | `33a5cbc233e0f4c4b0457f7d99f288f12dd7a97719f457ea5a90623eb4795812` |
| `app/serializers/listable_topic_serializer.rb` | `7768ea13a61e33f4164725b1ae717378a88dd1ddc10667a44eef260dfc47d66b` |
| `app/serializers/basic_topic_serializer.rb` | `42e4a354cf6c5c9da17aedeb45895170e0f55cca9e40190a29d4d13703b59f85` |
| `app/models/topic.rb` | `8202e548cd9ce289b61aca469449e282ce061b411a9b0551c0f1cd3b82455952` |
| `config/routes.rb` | `66ce2ecb978c2e5b8d084f242878ca9233761a25d984527d4f36ec6d5fa889c6` |
| `spec/requests/list_controller_spec.rb` | `d16f22f7738cd8baa81039e953d88db1159dbf6cb7a0d8a166b67f0efe4437f9` |

## Request and control flow

* Routes map `GET /latest.json` and `GET /latest` to `ListController#latest`; the HTML route is a list page (not an API representation). `latest` builds options, suppresses category-definition topics unless configured otherwise, calls `TopicQuery.new(current_user, opts).list_latest`, sets pagination URLs, then `respond_with_list`.
* `TopicQuery#list_latest` calls `create_list(:latest, {}, latest_results)`. `latest_results` is `default_results`, then muted-topic removal, shared-draft filtering, and registered plugin result callbacks. Thus a hand-coded SQL query must not silently omit those hooks/settings.
* `default_results` applies list pagination (`DEFAULT_PER_PAGE_COUNT`), default ordering, secured/listable topics, visible filtering, page offsets and request filters. For anonymous `current_user` is nil, so `visible: true` is selected; `Topic#listable_topics` excludes private-message archetypes, and `visible` excludes unlisted (`visible=false`) topics. Guardian category security also applies. Do not expose deleted, private-category, or private-message topics. Muted-topic exclusion applies for users; anonymous has no user mute state.
* Default descending ordering maps to `topics.bumped_at DESC` (unless selected category sort/configuration changes it). Listable latest can prioritize pins when ordering permits; the `latest` result itself may also include plugin result filters. Preserve Rails response sequence, not a client-side resort by created time/title.
* `TopicListResponder` serves JSON as `render_serialized(list, TopicListSerializer)` and HTML via `list/list`, with preloaded serialized list data. Both are dynamic Rails output; HTML includes application bootstrap and substantial theme/plugin/site-dependent markup.

## JSON contract

Top-level JSON envelope: object with `topic_list` (serialized by `TopicListSerializer`). `topic_list` serializer declares the following attributes, with conditional inclusion as controlled by serializer methods/site settings:

* Base keys: `can_create_topic`, `filter`, `more_topics_url`, `per_page`, `topics`.
* Optional list keys: `for_period` when present; `top_tags` when tag inclusion is enabled; `tags` when tagging is enabled and list tags exist; `shared_drafts` when present; `filter_option_info` when present; `filter_new_topic_ids` when non-nil; `categories` when guardian permits lazy category loading. `prev_topics_url` is populated by the controller but is not declared by this serializer, so do not invent it in output.
* `more_topics_url` is serialized only when present **and** returned topic count equals `per_page`.
* `topics` is an ordered array of `TopicListItemSerializer` records. Declared fields inherited/added by the serializer are:
  * Always-declared core: `id`, `title`, `fancy_title`, `slug`, `posts_count`, `reply_count`, `highest_post_number`, `image_url`, `created_at`, `last_posted_at`, `bumped`, `bumped_at`, `archetype`, `unseen`, `unread`, `new_posts`, `unread_posts`, `pinned`, `unpinned`, `excerpt`, `visible`, `closed`, `archived`, `is_warning`, `unicode_title` only when title contains an emoji shortcode, `thumbnails` only when configured by theme, `visibility_reason_id` only when present, `last_poster` when the object says it is included; and the TopicListItem fields `views`, `like_count`, `has_summary`, `last_poster_username`, `category_id`, `op_like_count`, `first_post_id`, `pinned_globally`, `featured_link`, `allowed_user_count`, `participant_groups`, `is_hot`, `is_nested_view`, `has_new_replies`.
  * Conditional fields: `notification_level`, `last_read_post_number`, `unread`, `new_posts`, `unread_posts` when user data exists; `excerpt` when pinned, setting/theme requires it; `op_can_like`, `op_liked`, `first_post_id` gated by theme/plugin modifier; `liked_post_numbers` when user post-action data includes likes; `featured_link` and `featured_link_root_domain` when enabled/available; `posters` when topic poster data exists; `participants`, `participant_groups`, `allowed_user_count` for private messages (not expected on anonymous public latest); plugin/theme modifier-dependent `is_hot`; and `has_new_replies` only for a signed-in user with nested view and qualifying unread data.
  * `posts` are not embedded as a topic's full post list; list output is a topic summary. Discourse's serializer framework and current setting/theme/plugin state determine the exact emitted optional keys. The reference probe therefore compares the entire parsed JSON value, not only a hand-maintained subset of summary fields.

The list-level `filter` is `latest`; anonymous permissions make `can_create_topic` dependent on site settings/guardian. Timestamps, counters, generated URL values, site settings, plugin callbacks, topic updates and the database contents are live values—not suitable hardcoded response data. For two live servers on the same DB/settings, the comparison is strict JSON equality by default (including topic array order); any explicitly accepted volatility must be argued and separately documented, not silently dropped.

## Executed seeded Rails capture

`minimal/build/latest-rails.json` is a static verification artifact captured from the pinned Rails app using `capture-latest-rails.rb`. It is intentionally outside a serving path, ignored as task build output, and never read by a runtime handler. Capture command (from repo root after sourcing `harness/env.sh`):

```sh
mkdir -p minimal/build
cd discourse
DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development' \\
REDIS_URL='redis://127.0.0.1:6399/0' RAILS_ENV=development \\
bundle exec bin/rails runner ../minimal/reference/capture-latest-rails.rb \\
  > ../minimal/build/latest-rails.json
```

The runner explicitly opens an ActiveRecord transaction and executes `SET TRANSACTION READ ONLY` before any Rails integration `GET`; it captures anonymous `/latest.json` and `/latest.json?page=1`, plus a SELECT-only audit. No fixtures, seeds, app server, DDL, or database writes are involved. It aborts if any returned topic is not visible/regular/not-deleted, a topic in a `read_restricted` category leaks, category-definition topics appear while the setting is false, or global pins are not first in `pinned_at` descending order followed by remaining topics in `bumped_at` descending order. Output contains API bodies and selected public identifiers only—never site-setting secrets.

At capture time the source revision was the pin above. `/latest.json` returned **20** topics in order `[5, 15, 28, 25, 29, 18, 20, 17, 33, 24, 31, 32, 21, 16, 23, 26, 30, 19, 34, 27]`, `per_page=30`, `filter="latest"`, `can_create_topic=false`, `top_tags=[]`, and no `more_topics_url`; `/latest.json?page=1` returned an empty topic list with the same list-level keys. This fixture DB has 34 topics, all visible regular and not deleted; therefore it supplies no actual unlisted, private-message, or deleted-topic example. It does supply real order, empty second-page, category-security and category-definition checks. The three restricted categories are Staff (id 3), school (10), and International (12); their six topic IDs `[2, 4, 6, 12, 14, 22]` are absent from the response. Topic 22 is a non-definition topic in a restricted category, so this is an actual security exclusion independent of definition filtering. There are 11 category-definition topics `[1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14]`; `show_category_definitions_in_topic_lists=false`, and none occurs in the returned list.

With topics present, the **actual top-level response** includes `topic_list`, `users`, `primary_groups`, and `flair_groups` (the latter three are preloaded serializer records, absent on the empty page-1 body). `users` has 22 entries (system plus 21 topic users); first returned topic 5 has poster `{user_id:-1, primary_group_id:42, flair_group_id:42, extras:"latest single"}` and matching `last_poster_username:"system"`. Poster entries for two-poster topics preserve the OP then most-recent poster and their role `extras`; users/groups are de-duplicated preload tables, not nested full profiles on every topic.

The captured topic key union (20 topics) is exactly: `archetype`, `archived`, `bookmarked`, `bumped`, `bumped_at`, `can_vote`, `category_id`, `closed`, `created_at`, `excerpt`, `fancy_title`, `featured_link`, `has_accepted_answer`, `has_summary`, `highest_post_number`, `id`, `image_url`, `last_posted_at`, `last_poster_username`, `like_count`, `liked`, `op_like_count`, `pinned`, `pinned_globally`, `posters`, `posts_count`, `reply_count`, `slug`, `tags`, `tags_descriptions`, `title`, `unicode_title`, `unpinned`, `unseen`, `views`, `visible`. All except `excerpt` and `unicode_title` occurred on all 20; each of those appeared once because topic-specific content caused inclusion. `can_vote` (topic voting) and `has_accepted_answer` (Solved), plus tag descriptions, demonstrate plugin/concern additions beyond the core serializer declaration. Current seeded tags are empty, image URLs null, and all stored `fancy_title` values are populated (the native adapter rejects uncached values rather than invoking Rails title generation). The capture is the authority for exact **current site** keys and values; source-derived possible keys remain setting/plugin-dependent.

For a direct candidate comparison against the saved capture (no Rails process required), run `DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development' REDIS_URL='redis://127.0.0.1:6399/0' minimal/reference/compare-latest.py --compare-recorded minimal/build/latest-rails.json --candidate http://127.0.0.1:3499`. This compares the complete parsed JSON body for both page requests, strict key/value equality and array order; it does not prune keys or normalize dynamic fields. Refresh the static capture explicitly when the Rails seed changes. The Rails HTML request currently returns 503 because this reference checkout has no `frontend/discourse/dist/manifest/manifest.json`; no HTML response is captured. Its source/spec contract remains in the following section for later frontend comparison.

## Visibility/order cases to ratchet

1. Public, listable, visible topic occurs once, in Rails order; changing `bumped_at` / adding an eligible topic changes response/order.
2. `visible=false` topic is absent for anonymous latest.
3. Private-message archetype is absent from public latest, even if otherwise visible.
4. Topic in a category the anonymous guardian cannot see is absent; permitted public-category topic appears.
5. Deleted topic is absent; category definition is omitted when `show_category_definitions_in_topic_lists` is false (the controller sets `no_definitions`).
6. Default order is bumped-at descending; pins/category sort settings and plugin callbacks can alter it and must be treated as configuration/extension behavior, not assumed away.
7. Page/limit response preserves Rails `per_page`, order and conditional `more_topics_url` semantics. Anonymous output does not have per-user read, like, bookmark, mute, or unread state.

Upstream request specs include `list_controller_spec.rb`: anonymous HTML structured data (`.topic-list`, `[itemprop="itemListElement"]`, position/url), JSON route checks, tags/categories behavior, and separate fixtures for visibility/security/muting in query/filter tests. Specs constructing or updating fixtures are not run against the task DB by this ticket.

## HTML contract

`/latest` is an HTML document generated by Rails `list/list`, with application layout/bootstrap and a topic-list structure. A future browser contract probe must compare the semantic DOM signature (element names, classes, `itemprop`, and `content`/`href` attributes), not volatile text, script payload, asset URLs, or byte-identical markup. Known source spec requires `.topic-list`, each entry `[itemprop="itemListElement"]`, its `[itemprop="position"]` content (`1` for first item), and `[itemprop="url"]` href equal to the topic URL. Real frontend/assets/bootstrap are part of the goal; reproducing only this diagnostic table is not equivalent.

## Backend integration notes

Start with actual runtime row data and the task-owned DB (`DATABASE_URL=postgres://discourse@127.0.0.1:5499/discourse_development`) and Valkey (`REDIS_URL=redis://127.0.0.1:6399/0`). Never use implicit defaults. Reads should run in a PostgreSQL read-only transaction. Follow the source query stages above (visibility + `secured` category policy + listable scope + category-definition exclusion + default order/pinning + per-page); include hooks/settings that the minimal runtime can genuinely support and document unsupported plugin/theme effects. Do not copy a captured response into a handler. Keep response bodies, probes, and generated build output out of serving paths.
