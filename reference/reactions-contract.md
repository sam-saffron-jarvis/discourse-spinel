# Bounded anonymous reactions users-list contract

Source: Discourse `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`, shipped
`discourse-reactions` core plugin. Original plugin sources (routes, controller,
query, filter, models, settings, plugin declaration, caller and request specs)
are retained **byte-for-byte**, source-only, under `reactions-upstream/`.
`SOURCE_MANIFEST.json` hashes these sources plus the core Guardian, User,
ApplicationController, settings and action-type dependencies. Build/runtime never
load the reference copies or Rails oracle outputs.

## Extracted behavior

- Anonymous `GET /discourse-reactions/posts/:id/reactions-users-list.json` and the
  actual source extensionless `/reactions-users-list` route. The upstream caller
  is `CustomReaction.fetchReactionsUsersList(postId,page,limit,reactionValue)`;
  this is **not** the separate `/reactions-users` grouped popup endpoint. The
  source action renders JSON for `.json` or extensionless JSON Accept/XHR. A plain
  extensionless HTML request is intercepted by ApplicationController#check_xhr
  (`RenderEmpty` and the Rails shell, not the plugin action). This checkout's
  fresh oracle observes500 in that unbuilt shell. Native returns explicit501
  instead of inventing users-list success or claiming shell/error-template parity.
- `requires_plugin` maps a disabled `discourse_reactions_enabled` plugin to404.
  Both native and source dependency fixtures exercise disabled behavior without
  changing the live setting. Live enabled setting overrides are SELECTed each
  request. No plugin boot DSL, registration or modifier runtime is implied.
- `Post.find` undeleted scope, then anonymous `Guardian.ensure_can_see!(post)`.
  Absent/deleted post404; extant inaccessible post403. Reject PMs, deleted topics,
  shared drafts, restricted/missing categories, whispers/unknown post types.
  Direct unlisted topics remain viewable, as in Guardian (not latest-list scope).
  Hidden posts require source granular anonymous permission and group4 in
  `hidden_post_visible_groups`; otherwise403, **not** a cooked placeholder.
- Source `page.to_i.clamp(0..)` and present `limit.to_i.clamp(1,50)` (default30).
  Scalar junk coerces to0, decimal prefixes work, negative pages clamp to0,
  blank/ASCII-whitespace limits default30. Page is a zero-based offset times limit.
  The pinned app loads fast_blank1.0.1 `rb_str_blank` (ASCII whitespace/NUL), not
  ActiveSupport's Unicode `blank_as?`: NBSP is therefore a specific filter and
  a present limit coerced to0/clamped1. The native predicate and actual source
  fixture match that dependency, whose C source hash is in the manifest.
  Source single-underscore digit prefixes (`1_02tail` ->102) are also retained.
- `Reaction.main_reaction_id`: live reaction-for-like setting, hyphens removed.
  Absent/blank/whitespace reaction filter selects all. An exact main filter
  selects **plain likes only**, not historical main ReactionUser rows. Other
  nonblank values select exact reaction values, including disabled/historical
  values. No invented enabled-reaction, count-nonnil, active-user or profile
  visibility filter: none exists in this source action/query. In particular
  `hide_user_profiles_from_public` does not hide this source endpoint's reactors.
- Source strict shadow-like suppression: a like (action type2, not deleted) is
  excluded when **any** ReactionUser has the same post/user, independently of
  reaction value, counters or current enabled-reaction settings. Reactions and
  surviving likes use `UNION ALL`, ascending `created_at`, source limit/offset.
  Ties intentionally have no invented secondary ordering, just like source.
- Rows join users; totals do not. Orphan fixture rows may count without yielding
  a user. This source asymmetry is preserved rather than silently repaired.
  `users` contain username, conditional name, avatar_template, id, reaction;
  `total_rows` is the source total independent of pagination. No timestamps or
  user private fields are emitted. Names disappear entirely when enable_names
  is false (including nil/empty names when enabled, just as `format_user`).
- Source uses the **class** `User.avatar_template(username, uploaded_avatar_id)`;
  the system-user instance-logo shortcut does not apply. Native reuses the
  existing ASCII task-site letter/upload avatar adapter without an identity ID.

## Explicit native adapters and unsupported boundaries

`lib/reactions.rb` translates ActiveRecord/MiniSql to parameterized PG SELECTs
with source table/joins/predicates and native JSON records. It is an adaptation,
not unchanged compiled Rails. Requests run in read-only repeatable-read
transactions, always rolled back, over the existing task PG5499. No Ruby,
Python, Node, Rails server/proxy/subprocess is involved in native serving.
The socket/path/JSON/PG/profiler adapters are the same as latest/topic.

Only canonical unsigned32-bit-range decimal IDs (including absent0) and bounded
scalar params are accepted. Query<=2048 bytes, each decoded value<=256 bytes;
integer prefixes must fit signed32 bits (offset uses64 bits). Negative IDs,
encoded/ambiguous ID forms, arrays/hashes, duplicate/unknown params, malformed
percent escapes, decoded NUL/replacement-character values and huge integers return400 instead of Rails' broader coercions,
ignored options, errors or post_id override. This deliberate fail-closed boundary
never broadens visibility. Error body envelopes/templates are app-owned, not a
claim of Rails exception-body parity. Cookies/API auth are never interpreted.

Login-required sites fail closed403; auth/login redirects are not implemented.
ASCII task-site hostname `localhost`, default external letter-avatar template and
uploaded avatar version2 remain the bounded avatar contract. Non-ASCII usernames,
custom default_avatars, empty external avatar URLs fail explicitly rather than
return invented avatars; source Unicode/default-avatar behavior is not extracted.
Root JSON avatar URLs are not rebased, matching upstream class getter bytes.

The distinct grouped post-reactions-users slice is documented independently in
`reaction-summary-contract.md`; its semantics are not derived from this query.
No writes/toggle/authenticated behavior, ignored-user state, reactions-given or
received, remaining routes, frontend plugin bundles,
UI changes, plugin topic serializers/hooks/jobs or full plugin support is claimed.

## Executable evidence

`source ../harness/env.sh; make plugin-test` rebuilds the native ELF and checks:

1. Original source hashes/copies and existing profiler asset/license provenance.
2. Compiled native read-only **synthetic** CTE fixtures using the exact runtime
   SQL/serialization, plus request clamps, visibility and settings guards.
3. The **unchanged actual** upstream PostReactionsQuery rows/total and controller
   format_user on the same synthetic typed CTE tables. Test-only query adapters
   prefix CTEs, never replace results; an injected main setting is process-local.
   No DDL/temp tables/seeding/reset; positive cases are never labeled live data.
   Actual Post.find/Guardian also runs against identical synthetic post/topic/
   category/shared-draft CTEs for the negative visibility cases. Main reaction
   and enable_names are explicit in-process setting dependencies, never PG edits.
4. A fresh actual anonymous Rails/plugin integration-session oracle against live
   visible task posts (and absent/denied/deleted examples if available), using
   source Guardian selection, filter/clamp and extension contracts. The oracle
   uses read-only PG and reports actual sampled reaction/like counts. Disabled
   source callback is a separately labeled in-process dependency fixture, not a
   claim that the live setting was changed. No captured values become runtime data.
5. Real native HTTP equality with every emitted source key/value, root/prefix and
   stripped proxy paths, profiler0/1 byte parity, malformed/security boundaries,
   actual redacted PG profiles and no residual request state or subprocesses.

Private evidence: `build/plugin/{rails-live,source-fixtures,report}.json`, logs,
and `build/reactions-fixtures-native.json`. Empty live data is useful parity but
never substitutes for positive source fixtures. Existing smoke/browser/topic,
actual upstream profiler and negative boot/reload tests remain separate contracts.
No live3499/Hub deployment or public health claim.
