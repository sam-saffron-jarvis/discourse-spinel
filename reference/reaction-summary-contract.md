# Bounded anonymous per-post reaction summary

Pinned Discourse `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`, shipped
`discourse-reactions`. Original routes/controller/models/filter/settings/caller/
request specs remain byte-for-byte in `reactions-upstream/`; source dependencies
are hashed in `SOURCE_MANIFEST.json`. This is a second, distinct read-only slice,
not a substitution of the ticket010 users-list query or full plugin support.

## Source action and transport

`CustomReaction.findReactionUsers` calls
`GET /discourse-reactions/posts/:id/reactions-users.json`, consumed as
`{ reaction_users: [{ id, count, users }] }`. The extensionless route returns
JSON with JSON Accept or XHR, as in the actual Rails integration oracle. Plain
extensionless HTML goes through ApplicationController#check_xhr/RenderEmpty and
the unextracted Rails application shell: native explicitly returns501, never an
invented successful summary. Source error-template/body parity is not claimed.
Only GET is supported; writes/other methods return405.

The source `fetch_post_from_params`, disabled-plugin callback and anonymous
Guardian boundary are shared with010. Native reuses its undeleted Post.find
lookup and direct post/topic/category/hidden visibility projection, including
unlisted direct links, private/deleted/whisper/shared-draft denials and the
explicit granular hidden-post group4 setting. Disabled plugin404, missing/deleted
post404, extant inaccessible post403; login-required sites fail closed403.
No reaction query is issued after failed access. Profile visibility settings do
not invent a profile filter absent from this anonymous source action.

## Distinct summary semantics

- **Absent** reaction_value selects all. Empty and whitespace strings are exact
  specific filters, NOT the users-list's `blank?`-means-all behavior. Exact main
  selects likes plus historical main rows under the source condition below;
  other values select that reaction, even if currently disabled.
- `Reaction.main_reaction_id` removes hyphens from the live reaction-for-like
  setting. `valid_reactions` is its set union with the enabled-reactions setting
  split on `|`. allow-any-emoji and excluded-from-like are NOT added to the
  summary's SQL predicates: source does not use them here.
- Source `filter_reaction_likes_sql` excludes active likes with a ReactionUser
  whose definition has a valid reaction value. The separate historical-like
  exclusion removes likes associated with now-disabled reaction values. Deleted
  likes and other action types are excluded. Both correlated predicates and SQL
  NULL behavior are preserved, not replaced with010's strict any-row exclusion.
- Reaction definitions with a NULL stored reaction_users_count are omitted;
  zero is truthy in Ruby and is retained. Non-main definitions are selected
  without an enabled-reaction filter. Anonymous counts are the **stored counters**,
  not a recomputed distinct actor count or the capped users length. No invented
  reaction-definition order or secondary timestamp ordering is introduced.
- Main summary is emitted **only if surviving likes are present**. Like count is
  the full untruncated relation length. format_likes_users takes the first27
  source relation rows, with **no ORDER BY**. If a historical main definition
  has a non-NULL counter, get_users contributes its most recent27 ReactionUsers,
  its stored count is added, and the serialized user timestamps are sorted
  ascending. Source then reverses and takes27. Without that historical-main
  branch it simply reverses the original first27 likes; this is deliberately
  not a repaired newest27 query. Historical main alone with no surviving like
  yields no main entry, even if its stored counter is positive.
- Other groups load ReactionUsers ordered created_at DESC and limited to
  MAX_USERS_COUNT+1 (27). No DISTINCT is added; actors shared between a like
  and a historical main/reaction remain governed by the actual source filters.
- Each user has username, conditional name (omitted when enable_names is false),
  **instance** avatar_template, can_undo and created_at. Unlike010 the system
  user's source small-logo shortcut applies. ReactionUser#can_undo? compares
  created_at strictly against the live post_undo_action_window_mins (default10)
  ago, even for an anonymous viewer. Anonymous likes cannot be undone, via
  Guardian#can_delete_post_action?. Timestamps use the source UTC Time#to_s
  seconds string, not ISO8601/milliseconds. No user ID or reaction field is
  added to these user objects.

## Native adapters and explicit narrower support

`lib/reaction_summary.rb` adapts ActiveRecord relations and the actual helpers to
bound PG SELECTs/native JSON, not unchanged compiled Rails. Requests use task
PG5499 read-only repeatable-read transactions, always rolled back. UTC SQL/session
formatting implements the pinned UTC created_at.to_s behavior. Time.now is sampled
once per native summary; exact undo-window boundaries can race in real source
requests too. No Ruby/Rails/Python/Node subprocess, proxy, persisted response,
source fixture or oracle data participates in native serving.

Only canonical decimal IDs0..2147483647, a single optional scalar reaction_value,
query<=2048 bytes and decoded value<=256 bytes are supported. Unknown/structured/
duplicate params (including post_id/id override), malformed percent/UTF-8/NUL and
noncanonical IDs fail400 rather than Rails' broader coercion or ignored options.
Authorization/API/shared-session credential headers and a nonempty default _t
login-token or _forum_session cookie are
explicitly rejected403 on this endpoint; cookies never authenticate. Authenticated
ignored-user behavior and login redirects are not extracted. Existing ASCII
task-site upload/letter-avatar adapter applies; non-ASCII avatar usernames,
custom default avatars and empty external templates fail rather than fabricate
source avatars. Missing associated users also fail, not a shortened success.
No writes, other reactions routes, plugin boot/hooks/jobs/serializers/frontend UI,
all-core-plugin parity or public Hub/live3499 deployment is claimed.

## Executable evidence

`source ../harness/env.sh; make reaction-summary-test` actually compiles the native
ELF, runs positive SELECT-only typed CTE fixtures through the runtime summary
SQL/serialization and compares to the **actual unchanged source action/helpers**
on the same source-driven fixture rows. Test-only in-process settings/clock and
post/response dependencies are explicit; no live setting/table writes or DDL.
The same test captures a fresh actual anonymous read-only Rails/plugin HTTP
oracle, then checks root/prefix and stripped paths with profiler0/1 response-byte
parity, denied/missing/plugin/privacy/transport/parameter cases, native ELF/no
children and cleanup. Actual redacted SQL timings are retained without binds,
filter values, credentials or cookie data, including branch and state-isolation
checks. Source-driven positive fixture evidence is labeled separately from live
empty-data parity when task likes/reactions are zero.

Evidence lives only in ignored `build/reaction-summary/` and
`build/reaction-summary-fixtures-native.json`; it is not runtime input. Existing
plugin-test, smoke, latest/topic browser, upstream profiler and injected502+Reload
contracts remain required independently.
