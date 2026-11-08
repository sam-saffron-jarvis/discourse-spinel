# Recovery29 — executed HTML request/controller prefix, not HTML200

SAME019 / same safe session/source trees. Base checkpoints Fidelitye804bab /
Roundhousee37a17673 preserved. Gate28's failed legacy full settings declaration is
NOT retried or accepted. Native JSON150855, readonly baselines223727/225056 and all
Recovery28 CSP/assets results are preserved. Full019/originalHTML200/nativeHTML/
browser/page acceptance remain FALSE.

## Source investigation and selected scope

The original route is the `Discourse.filters.each` declaration in
config/routes.rb, expanded only for latest. ListController skips check_xhr; its
ordinary ApplicationController before callbacks still apply. In declaration order,
these include readonly/theme/actor/snapshot/locale/profiler/login guards, then
`preload_json` and `initialize_application_layout_preloader`. Contrary to treating
all HTML acquisition as immediately forbidden, these last two operations are
write-free: the first allocates the HTML preload marker, and the second executes
the real preloader constructor. `preloaded_data` is a DIFFERENT, later operation.

The actual latest action then executes the genuine TopicQuery/list hydration,
paging and HTML-only metadata. TopicListResponder's HTML block stores the freshly
serialized list via the real preloader storage method BEFORE `render "list/list"`.
This is a useful independently executable request-stage integration. It does not
require manufacturing Site/settings preloads or invoking the forbidden cold Site
branch. The continuation therefore implemented/executed it rather than stopping
at source analysis or repeating helper-only vectors.

## Executed request path

`make verify-html-request-stage` runs tools/probe_latest_html_stage.py. It creates
a fresh source-backed native input with tools/project_latest_html_stage.rb,
compiles AND RUNS it, and compares SAME lowered CRuby. The sole platform difference
in emitted Ruby is runtime/pg_driver.rb; all source hashes are recorded.

Separate strict admission permits only direct-loopback, anonymous GET `/latest`,
exact text/html Accept, no proxy/credentials/cookies/XHR/body/format override and
no browser-UA context. The old JSON ingress and base profiler still require
`/latest.json`; neither admits HTML. Shared direct-context checks are factored,
not weakened. A stage-specific profiler subclass uses those same guards. No
public transport/listener/service/HTML endpoint is installed.

The real request/router/controller/callback machinery executes through the HTML
marker, genuine constructor, real query/hydration, HTML metadata, real serializer
and genuine derived-list storage. The original render call is replaced by a
specific HtmlRenderingBoundary exception BEFORE execution. There is NO fabricated
HTML/status200 response, no Content-Type relabeling and no JSON-only ingress.
Source callbacks are not skipped to produce a success. The exception unwinds the
locale/controller/profiler/query-session/interlock/connection scopes; rendering
and its following after callbacks are explicitly UNEXECUTED, not accepted.

New source projection records exact hashes/spans and every adaptation:
- Fixed original latest dispatch, original HTML metadata and static HTML responder
  block. Original source paging emits JSON paging URLs even for HTML; this does
  NOT make the request/response JSON.
- Source-proven uncategorized /latest branch only. Shared drafts, categorized
  ingress, authenticated redirects and enabled content localization refuse.
- Actual RSS route URL helper for feed availability; not full Rails route-set
  reflection equivalence. Native theme env-key translation is reused.
- Actual Theme/ThemeModifierSet queries for homepage metadata, original menu item
  construction, source-derived no-plugin register initialization. Configured/
  custom/registered-plugin homepage profiles and applicable settings-default
  modifiers explicitly refuse, never disappear or become forced flags.
- The needed Homepage enum is proved unwrapped from its pinned class. Only that
  required read contract is added; other special getters still refuse. The live
  top-menu getter needs its REAL upcoming-change default override. The bounded
  read contract preserves actual DB/config precedence, stored opt-out, source
  status/promotion/default behavior and unsupported type/profile refusal. It is
  NOT full upcoming-change activation or SiteSetting initialization. No settings
  setter, callback, production value or wizard flag is forced.
- Fresh list JSON uses the existing accepted fixed TopicListSerializer bridge,
  not application SQL or hand-built JSON keys. Original store_preloaded preserves
  script-closing safety. Its input is genuine newly queried/serialized data, not
  saved oracle output. The isolated encoding regression is explicitly UNIT-only
  on a separate preloader and never fed to the request.

## Final executed evidence

**build/probe-portable-security-20261108-000503/evidence.json — PASS_PARTIAL_HTML_REQUEST_STAGE_NOT_HTML_RESPONSE**

- Fresh native compile330.17s, actual native execution0.114s; same-lowered CRuby
  and a separate original-method comparison process match. Two requests:
  `/latest` materializes20topics, `/latest?per_page=2&page=1` materializes2.
-72observed native SQL statements, with actual topic/category/user/theme/modifier
  materialization. No observed DML/DDL. Entry guards require BOTH physical PG
  connections on5499 readonly ON before application queries.
- Native trace1execve, exactly2readonly PG connections +1separately owned guarded
  disposable cache connection, no Ruby child. No sharedValkey6399 mutation.
  All owned fixture endpoint/ownership/configuration checks and cleanup pass.
  This exception-prefix makes ZERO cache writes; no profiler save/header/body
  effects are claimed after the refusal.
- Exact callback stage order: preload marker -> constructor -> action -> HTML
  responder. Real title/description/RSS, guardian/theme/target/login-method types,
  full derived payload and topic IDs agree. Context/query/session/interlock/pool
  cleanup is checked at the normal rendering boundary.
-7ingress negatives/runtime reject JSON Accept, POST, nonloopback peer, forwarded
  peer, credential cookie, untrusted host and format=json override, with context
  cleanup. Admitted host headers also update the materialized Request before
  HostAuthorization, avoiding a stale env/Request host split.
-4compiled negative controller variants, each RUN under native AND CRuby, reject
  omitted HTML marker, omitted derived storage, duplicate marker callback and
  corrupted acquired theme.2additional endpoint negatives refuse BEFORE connect.
  Thus10request-stage negative executions beyond the ingress matrix; owned
  fixtures are cleaned after success AND failure.

## Isolated exact originals, without another original Rails HTML request

`generate_html_stage_original_methods.rb` executes20unmodified original method
spans: UpcomingChanges predicates/statuses/dependencies, DefaultsProvider read/
activation-set methods, preloader constructor/storage and preload_json. Its
acquisition adapter reads FRESH actual store state and immutable declarations in
a separate CRuby process. No supplied production settings, SQL rewrite, saved
response or copied runtime-state file is an input. Actual Actionpack MIME objects
supply the original request-format protocol; cached gem/member provenance is
verified. The source Enum is also original, not a made-up status table.

These methods prove the scoped read/default/marker/storage contracts. They are
NOT an original Rails HTML oracle, complete original controller/framework
execution, original full serializer initialization, full settings reload or
production upcoming-change activation proof. The prior JSON serializer/query
proof remains separate. No original Rails HTML request was invoked in29.

## Verification, preserved failures and remaining boundary

- Final run log: build/recovery29/final-host-stage.log.
-10existing JSON request owner/source tests PASS; original/shared/native direct
  peer+strict JSON ingress PASS. Source manifest + generation reproducibility
  2tests PASS. Owning store controls include promoted default, stored opt-in/out,
  explicit old-default menu override, promotion-never, global menu precedence,
  invalid type and unknown-status refusal. No full declaration campaign.
- Rebuilt cumulative readonly baseline **build/verify-20261107-235738 PASS**;
  baselines223727/225056 preserved. Original scoped oracle/cache/log fixture only,
  not HTML. No protected harness or gate changed.
- Failed diagnostics retained under build/recovery29 and individual build dirs:
  provenance regeneration, class-owner merge, optional category analysis, argument
  contract, necessary special getters, replacement-string backslash handling and
  isolated original protocol dependencies. They were diagnosed/fixed; no gate or
  source guard was removed to obtain PASS. Native successes231917 and233256 plus
  fixed original-method/control diagnostic remain preserved too.

**The next original operation is `render "list/list"`, not more isolated helper
work.** The genuine application layout can acquire stylesheet/theme content and
calls ApplicationLayoutPreloader#preloaded_data -> preload_anonymous_data ->
Site.json_for -> SiteSerializer -> Wizard.requires_completion?, reaching the real
bypass_wizard_check setter on the established cold conditions. Original stylesheet
cache INSERTs are also already observed indispensable effects. This continuation
REFUSES before that original rendering/acquisition; it does not execute it merely
to rediscover the write failure. No fake Site/preload data, skipped callbacks,
forced flags, warm oracle state or canned page may bridge this boundary.

Built CSP and nonce machinery from28 is PRESERVED, not promoted from unit vectors
to acquired request policies. Production CSP acquisition/serialization and body
nonce insertion have NOT been reached on this HTML request: the original policy
middleware builds headers after the application returns, which this stage never
does. Reusing unit CSP/extension inputs here would be false integration.

NOV7 approval is still CONSUMED, exactly1failed original HTML invocation and prior
cleanup verified. No snapshot/dump/restore/private-PG reuse/new HTML reference,
native/compat PG writes, permission question or repeated notification occurred.
Crossing the next genuine rendering/effect boundary needs separately reviewed
scope/authority and actual source-backed execution, not reuse of that approval.
Historical refused context remains archived/unresolved and was not replayed,
rerouted or rephrased; this is independent request/source work.

## Clean committed verification / final integrity

Implementation **903e14c**, host refinement **07eecc2**; Roundhouse **e37a17673**
unchanged/clean. Final committed-source cumulative readonly baseline
**build/verify-20261108-001315 PASS** (log
build/recovery29/committed-readonly-baseline.log), all guarded PG observations
readonly ON and owned original-scope fixture child-exited cleanup verified.
Prior235738/223727/independently gated225056 remain preserved, not relabelled.

Final audit build/recovery29/source-audit-final.json: all27,435blobs in BOTH
original checkout and genuine frontend source copy still match pin, including
symlinks; canonical aggregate1e1d4bbf63d2888ac507550b8c3ed0fbb3026d123b1853bef4b295194869d9c0.
Recovery28 policy/nonce/three-fragment source bytes are unchanged. Consumed
approval SHA45ef2a1be8bc05a4ebade3ebd7948218049df732bdabcee50bd4260120fc4ca7,
exactly1failed original invocation, cleanup and archived unresolved refusal are
unchanged. Spinela1a1bea71/original96ce8d4/minimalc975ee1 clean.

Quota41%/75soft/80hard, task plus all retained related trees about94.5GiB/150cap;
mainCPU0–3/max4,aggregate8, unchanged Nov8 16:27:43Sydney168hdeadline. No helpers,
revivals, helper-tree edits, protected harness/tickets/docs/ledger changes,
publication/deploy/Hub/demo mutations or persistent service changes. This is a
completed bounded HTML request-stage dependency; it is NOT full019 or a page.
