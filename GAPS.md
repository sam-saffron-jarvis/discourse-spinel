# Minimal extraction gaps — ticket 004

This is a scoped native **anonymous JSON** implementation on the task-owned site,
not a compiled Rails application. `SOURCE_MANIFEST.json` distinguishes source
extractions, adaptations and runtime adapters. No captured Rails body is served.

## Implemented and verified

- `/srv/status`: native TCP HTTP response after a live read-only PostgreSQL query.
- Anonymous `/latest.json`, `page=0..2000`; `/latest` also returns JSON for
  `Accept: application/json` or XHR. Unsupported filters/methods are rejected.
- Deleted/unlisted/private-message/restricted-category exclusion; optional category
  definitions, shared-draft category exclusion and default-muted categories.
- Global-pin priority by `pinned_at`, remaining topics by `bumped_at`, 30-row limit
  and pin-adjusted pagination. Local category pins do not jump to the top.
- The **entire seeded JSON response**, including root users/primary_groups/flair_groups,
  exactly matches Rails for first and empty second page. Fields observed:
  `id`, `title`, `fancy_title`, `slug`, `posts_count`, `reply_count`,
  `highest_post_number`, `image_url`, `created_at`, `last_posted_at`, `bumped`,
  `bumped_at`, `archetype`, `unseen`, `pinned`, `unpinned`, conditional `excerpt`,
  `visible`, `closed`, `archived`, `bookmarked`, `liked`, conditional `unicode_title`,
  `tags`, `tags_descriptions`, `views`, `like_count`, `has_summary`,
  `last_poster_username`, `category_id`, `op_like_count`, `pinned_globally`,
  `featured_link`, `has_accepted_answer`, `can_vote`, and `posters`.
- List fields: `can_create_topic`, `filter`, `per_page`, `top_tags`, `topics`;
  `more_topics_url` is conditional on a full 30-row page. The seeded list has only
  20 rows so URL generation is source-derived, not established by live Rails parity.
- Native SELECT-only synthetic CTE tests cover security cases absent from seed,
  changed-data ordering, categoryless NULL behavior, and multi-page global pins.
  Shared database rows are never changed, even temporarily.

## Missing / deliberately narrowed scope

| Path | Construct/scope | Current boundary | Required next work |
|---|---|---|---|
| `bin/discourse.rb`, `frontend/` | Real browser `/latest` document | HTML request returns **501**, not a handmade table. Core Ember JS builds independently but is not served. | Implement dynamic, client-safe `site` and `siteSettings` preloads, actual document/setup/import-map generation, static routing, locale/icon/CSS assets, widget-prefix handling; then verify browser DOM/network. |
| `lib/latest.rb` | Full ActiveRecord `TopicQuery` and request options | Explicit anonymous SQL **translation**, not unchanged Discourse code. Only default latest ordering and page supported. No arbitrary category/tag/search/sort/custom field filters. | Extract each option and its guardian/plugin behavior with value-for-value oracle tests. |
| `lib/latest.rb`, `lib/serializers.rb` | Tag permissions/top tags | Any nonempty `tags` table returns 501. Empty tag arrays/objects are valid for the currently empty table only. | Carry visible-tag guardian, tag-group restrictions, sorting, descriptions, top-tag and muted-tag policy. |
| `lib/latest.rb`, `lib/serializers.rb` | Image/thumbnail/featured-link handling and title generation | Selected image uploads/thumbnails, uncached fancy titles, or nonempty featured links return 501; `image_url=null` and `featured_link=null` are only served when warranted by live rows. | Extract upload URL/security/thumbnail lookup, title formatting, and featured-link domain methods. No thumbnail jobs/DB writes are attempted. |
| `lib/latest.rb` | Alternate locale, localization, nested replies, mute-all category mode, default avatars, custom small logo, emoji deny list, plain title mode, solved empty box | These known unextracted configurations fail closed with 501. Current English/default settings are the tested scope; other theme/plugin/global-setting changes are not generally validated. | Extract relevant source behaviors; remove a guard only with real parity coverage. |
| `lib/users.rb` | Avatar normalization, deployment hostname, flair uploads | Non-ASCII usernames, flair image uploads and empty external-avatar URL fail closed. Task-site host `localhost`, root base path, default small-logo URL and optimized-image version 2 are explicit runtime adaptations from source defaults. | Native Unicode normalization; deployment hostname/base-path/CDN configuration; upload/secure flair URL adapters. Avatar/image URLs are serialized but not served. |
| `lib/latest.rb`, `lib/serializers.rb` | Authenticated state | Always anonymous. Cookies/auth headers do not establish a session. No unread/notification/like/bookmark state, private-message participant fields or authenticated create permission. | Session/auth/Guardian adapters and separate permission/parity tests. |
| `lib/latest.rb`, `PLUGIN_SUPPORT.json` | Core plugin registration and theme modifiers | Only selected Solved/topic-voting list attributes are adapted; no plugin boot/hooks/events, full plugin behavior, theme modifiers, hot score, OP-like extras, nested views, or plugin routes. | Explicit per-plugin extraction/runtime tests. Compiling core JS does not establish plugin support. |
| `bin/discourse.rb` | Server runtime | Small loopback-only sequential HTTP adapter, one read-only PG connection, connection-close responses. Valkey URL is validated but no Valkey connection/caching is used. Not a production Rack/session/websocket server. | Request timeouts/concurrency, connection recovery, proper HEAD/negotiation, cache/Valkey behavior as needed by extracted routes. |
| `bin/discourse.rb` | Topic and other APIs | No topic page, `/site`, `/site/basic-info`, assets, sessions, plugin routes or mutations; unknown route 404. | Browser bootstrap first; topic extraction is a later rung. |

Read-only Rails capture is verification tooling only. It is synchronous and exits
before the native smoke listener starts. `build/` evidence, responses, binaries and
assets are ignored by Git. No Rails process serves final native data.
