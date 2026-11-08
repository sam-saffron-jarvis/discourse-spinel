# Recovery31 — pre-execution effect classification / containment contract

This document is recorded BEFORE new cache-effect execution. It is a design and
source-review result, NOT evidence that a cache, template body or page executed.
SAME019/session20261107-085321-f206496e99b8e410. Standing authority is
run/NATIVE_COMPAT_SANDBOX_AUTHORIZATION.json (isolated cache/log writes only), not
the consumed Nov7 privatePG approval. No new authority is inferred.

## Reviewed original source and effect map

- category.rb:1125,1131-1133: initializes category_url DistributedCache; URL lookup
  reads local namespaced hash; cold miss computes URL from actual category state.
- lib/distributed_cache.rb: defer_get_set -> defer_set -> genuine asynchronous
  Scheduler::Defer.later('category_url_set'), eventually self[k]=v. No SQL writes.
- locked MessageBus5.0.0 distributed_cache.rb: initialize subscribes to
  /distributed_hash and registers; Manager#set publishes op:set, String key/value,
  origin, hash_key:category_url, actual app_version, user_ids:[-1],
  queue_in_memory:true. Local hash update occurs AFTER publish returns. Own-origin
  incoming replication is ignored by the original manager. Weak registrations,
  site namespace and origin/app-version filters must not be bypassed.
- message_bus.rb: Instance permits an independently configured real Redis backend;
  subscribe starts subscriber thread, default60s timer keepalive; channel encoding
  uses $|$site-id. Decoder dispatches only registered subscribers. No HTTP/Rack
  clients are created by this capability. destroy publishes unsubscribe sentinel,
  disconnects backend, joins subscriber and stops timer.
- backends/redis.rb: publisher/subscriber/reconnect/unsubscribe connections all
  derive from redis_config. LUA_PUBLISH atomically INCRs counters, ZADDs backlogs,
  EXPIREs and PUBLISHes on _message_bus_<db>; trims backlogs. This is category-cache
  replication inside the same Redis instance, not external message delivery.
  queue_in_memory:true preserves readonly-error retry buffering/flush thread;
  is_readonly? uses owned Redis SET/disconnect/reconnect. No other endpoint is
  selected in that path. Unknown scripts/keys/channels/payloads must refuse.
- scheduler/defer.rb + work_queue.rb + MessageBus::TimerThread: real site/user fair
  queue, worker thread and warning timer; development async remains TRUE. Worker
  with_connection uses actual RailsMultisite single-site NullInstance (not the
  configured-multisite path); verify!/clear_active_connections! run in ensure.
  These are checkout/health/release operations, not permission for PG writes.
  Log warnings and errors are cache/log effects only if their sinks are guarded.
- Discourse.handle_job_exception -> SidekiqLogsterReporter -> Logster logger:
  error reporting is NOT permission to start Sidekiq, scheduled jobs, plugin
  callbacks or external transports. Any missing/uncontained error reporter must
  explicitly refuse before its first unadmitted effect, preserve the original
  error and still stop/reap owned workers. No fabricated successful job.
- original message_bus initializer: single-site site_id_lookup returns original
  current_db/DEFAULT; configured backend uses genuine GlobalSetting provider
  precedence. Source max_backlog_size and clear_every are configuration reads
  (defaults100/50, NOT backend defaults1000/1); no captured effective map. Keepalive
  must not be disabled and Scheduler must not be forced into test/synchronous mode.

## Authority mapping and mandatory dispatch guards

Permitted only when ALL hold:

1. Reuse ValkeySandbox and OwnedCachePolicy, one fresh independently owned fixture
   per runtime/process case, bind127.0.0.1, db0, persistence disabled, known child
   PID/parent/config/ready evidence. No additional service is required: threads
   and cache pubsub live in the caller and its already-authorized fixture.
2. Every connection (publisher/subscriber/retry/cleanup) checks ownership and
   actual endpoint BEFORE connect, and every dispatch checks endpoint plus exact
   cache namespace/runtime lease. Shared6399, PG5499-as-cache, unknown endpoints,
   stale owner, wrong runtime or site/cache namespace refuse before dispatch.
   Verify socket INFO PID against owned child. No URL/env-only containment claim.
3. Only category_url cache replication and genuine bus lifecycle/keepalive traffic
   may publish/subscribe. No other channel, generic job, other cache, web consumer,
   external recipient, replica/failover/TLS/auth backend or arbitrary script.
   Redis is empty/fresh, has no external consumers; verify subscription and client
   ownership, and refuse foreign channels/messages rather than processing them.
4. Preserve actual subscribe/register -> cold miss -> defer enqueue -> async work
   -> real publication -> local update, plus normal source-permitted hit/races.
   Do not insert warm hits or force worker scheduling. Drain/join at test/process
   cleanup, NOT synchronously inside Category#url to change request behavior.
5. PG remains readonly on every pool and thread; scope release/health checks are
   real, not stubbed. Never execute application DML or reinitialize a private PG.
6. Success AND errors close only owned sockets/threads/timers and terminate/reap
   only the existing fixture child. Observe actual effects and wrong-output/order
   controls, not just enqueue success. Do not silently omit publication on error.

Conclusion from source review: the successful exact category-cache lifecycle CAN
fit standing isolated cache/log authority if these guards and genuine scheduling
semantics are implemented. Its MessageBus name is not a prohibition. This is a
recoverable implementation/containment task, not a new permission request.
Uncontained operations remain explicit refusing capabilities, never executed to
reconfirm a known boundary. Original-only isolated methods/template are allowed;
no second full original Rails HTML, privatePG/snapshot/restore, shared writes,
new persistent service, external jobs/messages, helpers or permission prompts.
Full019/HTML200/browser/page remain false. Acquiring this capability does not
resolve later stylesheet/Wizard PG writes. Source/hash/effect/test evidence and
final disposition will be appended after actual implementation/verification.

## Implementation/diagnostic update before cache-mutant runs (Nov8 03:31)

Actual contained shared CRuby and native now execute original async WorkQueue/
Scheduler/Timer and original Redis-backend Lua publication. Three-way original
URL/cache/Scheduler methods agree in030808 after the reference observer ID fix;
fresh032410 also passes inherited request/ingress negatives. These remain
DIAGNOSTIC, NOT accepted category capability/body/page: explicit cache-state,
subscription/publication/defer/error/ownership controls are being added next.

Native projection preserves source behavior for the acquired single category
cache topology, with documented bindings: nil-site subscription storage is a
typed registry (original reference uses actual Hash); strongly rooted Category
cache registrations retain that lifetime; nil-user fair-queue key has an internal
sentinel; factory is retained on its actual owner instead of nested Hash-default
Proc capture; actual async methods selected, uncalled capture_later/test mutators
excluded. The latter test-only metaprogramming incorrectly affected native
lowering even though not executed. Dev-only test abort_on_exception branch is
explicitly unsupported, not forced off by changing Rails.env/async. Local cache
lookup/publication/update use a reentrant monitor for native parallel workers.
Concrete cache/bus bindings and typed presence lowering preserve actual values.
No compiler source change or historical restricted compiler operation occurred.

The negative test controller variants required explicit forwarding of their
inherited around-callback (super, no changed body/assertions); without forwarding
native dispatch skipped the observer's event initialization and crashed. The
failure and diagnostic worker1/4 matrix are preserved; both worker counts failed,
so this was NOT evaded by forcing cooperative/synchronous execution. Native
remains SPINEL_WORKERS=4, async true. Default request runner guard is preserved
behind a dispatch hook; only this exact capability admits its additional owned
publisher/subscriber/cleanup connections. Original/reference source unchanged.

Upcoming negative-only mutants deliberately omit subscribe/publication, bypass
defer, invert update/publication order, or raise inside a deferred assignment.
They must fail, never become admitted production profiles. The deferred exception
reporter remains a fail-closed capability before unbound Logster dispatch; do not
claim the full original error-reporting subsystem executed. Every endpoint,
namespace/runtime ownership and closure/thread cleanup assertion must remain
active. Successful requests use no mutants, no sync/test mode, fake URL or warm
state. All additional cache traffic, including default heartbeat/readonly retry
if reached, must stay on the same owned endpoint and exact source lifecycle keys.

## Coherent executed cache checkpoint (Nov8 04:27)

**build/probe-portable-security-20261108-042032/evidence.json**:
PASS_SCOPED_CATEGORY_CACHE_REQUEST_ACQUISITION. Native compiled AND RAN; SAME
lowered CRuby and isolated raw-original Category URL/cache/WeakRef/Scheduler/
WorkQueue/LRU/Timer methods pass with fresh genuinely acquired request/category
state. Final URLs, local cache and actual Redis backlog values agree across all
three processes: observed4:/c/general/4,5:/c/getting-started/5. These are results,
not inputs. Two cold misses -> two real queued/finished jobs -> two successful
Lua publications -> two actual manager callbacks -> actual local updates. Real
hits subsequently reuse those acquired values without recomputing or publishing.
No warm value was injected; no production call waits synchronously for its job.

Default source development async stays true, actual thread/queue/reactor execute;
all owned Ruby threads return to pre-acquisition count1. Server backlogs are read
from the already-owned publisher connection, never supplied as production data.
The source no-worker stop sentinel is recorded separately from pending real work.
Unambiguous observer accessors avoid accidentally invoking Object#hash instead of
the cache's original hash reader; no assertion was removed to accept an identity.

20NEW native/shared negative runs pass: shared6399/unknown endpoint, wrong site,
wrong runtime, foreign inbound namespace before callback, missing subscription,
missing publication, bypassed defer, update-before-publication, deferred exception.
Legacy10request negatives and7ingress refusals/process also pass. Every negative
is nonzero with expected error, actual thread cleanup and owned fixture reap.
The deferred-error case preserves/refuses before unbound Logster reporting; it
is NOT acceptance of the full original job-error reporting subsystem.

Transport guards bind every publisher/subscriber/retry/cleanup socket to the live
owned child PID/parent/config before connect and verify INFO PID. CLIENT SETNAME
marks only owned client metadata; actual CLIENT LIST and PUBSUB NUMSUB verify
one in-process consumer/no foreign runtime clients before every publication.
Only exact source Lua, namespaced category payloads, internal heartbeat, readonly
probe and shutdown sentinel are admitted. Foreign message schema/origin/version
is refused BEFORE manager callbacks/Marshal handling; readonly retry cannot pick
another backend. All such operations remain on the independently owned instance.
No external job/message delivery, extra service or shared state is involved.
Native trace remains one ELF,2PG5499 +4owned-cache connections, no Ruby child.

Reproduce with `make verify-category-url-cache`. Older failed builds/runs and
all diagnostics remain under build/recovery31 and their individual build roots;
none is relabelled passed. Supported JSON150855 and canonical prefix010430 are
preserved. This checkpoint intentionally still raises at the old prefix after
actual URL/cache acquisition; it is NOT a completed list body/layout/page.
Next work is advancing that actual original list body, not stopping here merely
because the cache dependency now passes. Later stylesheet/Wizard PG writes remain
prohibited. No authority/permission notification or original Rails HTML repeated.

## Body advance / additional effect review BEFORE icon-cache execution (05:18)

Native/shared050410 render actual20+2rows, poster links/avatars, escaped titles,
date_only dates and pagination/head links. A raw-original diagnostic now matches
those full row/list prefixes (source select over genuinely materialized tag
association; no substitute tag data). Full body still refuses at RSS helper:
this is progress, not a stopping milestone or completed body/page.

The next applicable original metadata helper calls SiteSetting image URL readers.
Source site_setting.rb:424-431 delegates supported icons to SiteIconManager;
lib/site_icon_manager.rb initializes a SECOND DistributedCache('icon_manager').
Its opengraph_image declaration has width/height nil, fallback_to_sketch:true,
resize_required:false. It reads actual upload settings in declared order, falls
back to the original SKETCH_LOGO_ID(-6) SELECT, computes full CDN URL, and caches
that String through the SAME original defer/publication lifecycle already proved.
No OptimizedImage.create_for occurs in this getter: that is ensure_optimized!, a
different operation. Favicon/apple-touch declarations later needed by actual
layout head permit an OptimizedImage.find_by SELECT then original no-resize
fallback; no creation/ensure_optimized! is admitted. URL/CDN configuration is
acquired from the same real provider; S3/failover/unknown profiles must refuse.

This is a second fixed, strongly rooted cache in the SAME owned fixture, manager,
subscriber, actual Scheduler and backend, NOT a messaging subsystem expansion or
new service/authority. It fits the standing isolated cache/log permission only
with exact allowlisted hash keys/descriptors, per-cache origin/version validation,
actual upload/optimized-image SELECTs, publication/update and success/error
cleanup. It must not be initialized early by telemetry: acquire it only when the
original metadata/layout helper actually reaches it. Extend the existing guard,
never select an unguarded default MessageBus. No PG write, image optimization,
remote asset fetch, forced setting/flag or manufactured upload/URL is authorized.
After implementation, compare actual body/head and cache values with isolated
original helpers. Remaining stylesheet/Wizard PG effects are still prohibited.

## Complete actual list body/head checkpoint (Nov8 05:55)

`build/probe-portable-security-20261108-054819/evidence.json`:
**PASS_SOURCE_LIST_BODY_AND_HEAD_BEFORE_LAYOUT_HELPERS**. Fresh native compile
AND RUN; SAME-lowered CRuby and a third isolated original full Erubi template,
original poster/user/tag/date/RSS/metadata/legacy TagHelper method closure agree
on the actual complete body and captured head. Actual default20 rows/body35972
bytes/head887 and paged2 rows/body4327 bytes/head1042. Original renderer reaches
`view.view_flow.set(:layout, yield(layout))` AFTER the body, copies its actual
buffer, then invokes layout.render. This is now a completed list body, not a
helper vector; layout helpers still refuse, not a returned HTML response/page.

Pinned ICONS declaration, route and locked MIME declaration generate constants;
no observed upload/cache/URL is input. Actual opengraph lookup reads ordered
upload settings and the source fallback Upload SELECT, through a lazily acquired
second `icon_manager` DistributedCache. Native/shared/original local and actual
server cache values match. New cache is registered on the same actual subscribed
manager. All publication/worker/callback/queue/thread/endpoint/consumer/namespace
and cleanup assertions apply; subsequent actual icon hits must not recompute.
Only the three reviewed icon roles are admitted by transport/descriptor guards.
Raw-original can queue repeated cold lookups before its worker catches up: its
publication count is not required equal to the slower native run, but EVERY job
must publish/complete and server/local final maps agree, with no forced drain or
synchronous shortcut. No upload data/value/cache warm hit is injected.

Source-specific local-upload profile validates actual stored enable_s3_uploads
Boolean against its exact declaration (false required for this supported scope).
It does NOT remove conservative generated special-getter flags, admit scalar
fallbacks globally, change settings, or create/fetch remote assets. Existing
readonly upload-reader contract deliberately does not claim Rails uploads[]
cache support. Original legacy-tag call closure is selected unchanged: importing
all TagHelper would bootstrap global I18n and conflict with the isolated runtime.
Applicable raw TagBuilder/tag/escape methods are executed, not replaced by our
native renderer. Unsupported source branches remain explicit scope refusals.

20 inherited cache controls +10 request controls +7 ingress refusals/process
PASS, plus6 new native/shared complete-body/RSS/metadata corruption controls;
owned child fixtures/threads cleaned on success and errors. Native trace remains
one ELF, exactly2 readonly PG5499 +4 owned-cache connections, no Ruby child.
`make verify-list-body-head` reproduces this checkpoint.

Preserved failures include native unsorted RSS query vs CRuby (052912), source
selection/syntax/global-I18n import diagnostics, and earlier partial body/cache
attempts. Failed canonical evidence is not relabelled. 053841 passes diagnostic
body parity;054819 adds executable wrong-output assertions and fixed-role guards.
Next permitted work is actual layout helper continuation, not another initializer,
declaration/template-order campaign. No permission barrier is claimed merely
because a layout helper is not yet implemented. Stylesheet/Wizard PG effects
remain independently prohibited. Full HTML200/browser/page/019 remain FALSE.

## Layout continuation / color-cache effect classification BEFORE execution (06:15)

Actual layout-prefix CRuby and isolated original now reach application header ->
layouts/head -> actual favicon/apple-touch Upload + OptimizedImage SELECTs ->
discourse_theme_color_meta_tags. Source application_helper.rb914-991 calls
ColorScheme.hex_for_name; color_scheme.rb330,463-473 lazily initializes fixed
DistributedCache('scheme_hex_for_name'), then identical cold deferred set/cache
replication. This cache-only operation fits standing owned cache/log authority
IF bound to the same fixture/manager/scheduler and fixed reviewed descriptor;
it is NOT a PG permission barrier or a reason to stop for missing implementation.

Supported next scope must validate actual anonymous/cookieless theme/scheme state
from readonly Theme/ThemeModifierSet queries. Base palette source is the pinned
colors.scss declaration read by original ColorScheme.base_colors, not an observed
color supplied as input. Base ColorScheme/ColorSchemeColor construction is unsaved
in-memory source data; no save/create/update or callback is called by lookup.
Any DB/custom palette not faithfully supported must refuse before publication.
Only header_background key in this scoped helper; no cache clear/delete/marshal,
external job/consumer/endpoints, extra service, optimization, PG or source writes.
Unknown color/cache scope must refuse. Native/shared/original cache publication,
update, real hits, server maps and cleanup must still be checked.

Source review confirms downstream stylesheet Manager::Builder#compile can call
StylesheetCache.add -> ActiveRecord.create and cleanup DELETE, on cold cache or
missing DB counterpart for existing disk CSS. Those operations remain prohibited;
no source change to skip them, false warm preload or writable PG is authorized.

Color preflight062634/062709 correctly REFUSED the too-narrow base-only candidate:
actual acquired theme has configured palettes (source getter dark_scheme_id13).
No color publication dispatched. This is recoverable missing implementation, NOT
missing permission. Revised read-only scope selects genuine ColorScheme (original
remote_copy:false default scope), ordered ColorSchemeColor associations and
source palette fallback/ColorMath brightness. These are SELECT/local-memory/SCSS
read dependencies; ColorScheme save/create/cache-invalidation callbacks remain
UNREACHED and excluded from selected read roots. Dynamic scheme IDs/hex values
come from actual rows, never these diagnostic observations as input. Existing
fixed color cache namespace/descriptor remains; allow header_background keys with
source-generated dynamic scheme suffix, no arbitrary colors/jobs/publications.

## Import-map next dependency: write-free inspection classification BEFORE execution (07:00)

064340 actually executes the COMPLETE layouts/head and returns it into actual
application-layout buffer (1316bytes), then stops at layouts/plugin_js. It is not
page/HTML acceptance. generate_import_map calls theme_js_assets -> Theme.js_asset_info
-> Theme.compiler_version -> AssetProcessor.ember_version -> cached local V8 bundle.
The exact original PrecompiledBundle digest inspection proves current bundle EXISTS
and matches source dependencies (digest apid9mnqof8igauq2hy6o4pga, SHA256
421b49f09b31907610e90827f130f565e985b5e32408ba52e9c0facc979bfc66).
No external build is indispensable on this state. Missing native V8 support is an
IMPLEMENTATION gap, not missing cache permission; do not claim a PG barrier here.

Initial target5 catalog inspection was wrongly labelled extra_js: original targets
maps5=extra_scss,6=extra_js. That failed inspection remains preserved. Corrected
source-derived target inspection shows no child themes and current theme-1 has no
extra_js fields; other theme-2 data cannot justify a claimed PG-write barrier for
this request. No inspection observations are production inputs or cache warmers.

Independently permitted next inspection evaluates ONLY original AssetProcessor
context/version methods in a fresh process with real MiniRacer and source bundle.
Containment: copy original dependency files+verified cached bundle into a newly
owned disposable cache directory; original PrecompiledBundle may only read that
copy, external build callback raises before process dispatch. JS context has only
original logger callbacks (stderr), no host filesystem/process/network/PG API.
Actual source context initialization/eval/emberVersion/call_await/dispose are not
stubbed. No forced synchronous/test/thread flags; real configuration controls
mini_racer_single_threaded. Bound CPU0-3 and15s JS timeout; dispose on success/error,
remove exact owned fixture in ensure, exit fresh process for process-global V8
resources. This is original-only READONLY inspection, not native capability,
application payload, full Rails invocation, or a shortcut supplying version to
production. No runtime/controller/settings/source/PG/service writes authorized.

## Actual complete layout head checkpoint (Nov8 07:12)

`build/probe-portable-security-20261108-070435/evidence.json`:
**PASS_SOURCE_LAYOUT_HEAD_COLOR_CACHE_PREFIX**. Native compile AND RUN, SAME
lowered CRuby and isolated ORIGINAL full application layout/head agree on the
actual 1316byte layout prefix (default case), complete head partial, actual
optimized favicon/apple-touch SELECTs, canonical paged URL, color/light+dark
media tags, search metadata, anonymous CSRF/shared-session decisions. Body still
35972/4327bytes,20+2rows. This is NOT a full layout/page/response/HTML200/019.
Actual source order is body -> view_flow.set -> layout -> layouts/head -> color
cache -> head return -> layouts/plugin_js import-map acquisition refusal.

The third fixed owned cache scheme_hex_for_name uses the same guarded manager/
subscriber/worker/backend; all three runtimes agree on actual local/server color
maps. Every real queued assignment/publication/callback finishes; genuine hits
must not recompute. Added8 native/shared controls specifically omit color pub,
raise in its deferred assignment, use an unadmitted color key, drop visible color
tags.20 inherited cache +10request +6body/head controls and7ingress/process remain
passing. All threads/fixtures cleaned; native still1ELF,2readonlyPG+4ownedcache.

Source-compatible read adaptations: materialize actual color association for
Enumerable#find (SDK relation's find is ID-only); named colors alias uses an
explicit method; apply original remote_copy:false predicate at every outer
ColorScheme lookup, while base_scheme deliberately unscopes it. File.readlines
is read.lines in the lowered model, same real source bytes/line endings. Owner
mutex is declared before reads. Direct pinned acquisition adds only readonly
ColorScheme/ColorSchemeColor/ColorMath roots, no save/callback/write API acceptance.
Raw base fallback uses name/hex protocol over original base_colors parsed SCSS,
not injected colors or pretend persisted rows; actual configured palette read
and raw original lookup/metadata methods still execute. All adaptations are scoped
and do NOT claim a complete ColorScheme model/runtime.

Preserved failures:060525 compile constant representation;061611 original closure
captured last ICONS variable (fixed by retaining original each block, not injected
URLs); subsequent original association lookup needed actual belongs_to foreign-key
binding. Original infos/getter methods now execute under original lexical capture.
063226 native/shared passes; corrected raw-original diagnostic separately passes;
064340 fullhead three-way passes;070435 adds all color-specific controls. No
failed canonical attempt is relabelled. New Make target verify-list-layout-head.

Original AssetProcessor inspection is independently contained and PASSES with
real cached bundle/V8 eval/call_await/emberVersion/dispose, Ruby threads1->1,
owned sparse cache fixture removed; NO PG or external build dispatched. Its output
is inspection ONLY, never production input or native/layout acceptance. Native
V8 binding remains an implementation gap, NOT permission missing. Current request's
theme-1 has no children/extra_js fields; stale theme-2 data is not used to assert
an applicable write barrier. Downstream stylesheet/Wizard PG writes remain
prohibited. Continuing scoped work; no authority prompt or second Rails HTML.

## Bounded native VM feasibility probe effect review BEFORE build/run (07:16)

The V8 gap is implementation, not a permission stop. Investigating a strictly
bounded Ruby-free ORIGINAL MiniRacer C++ bridge for cached AssetProcessor version,
not a generic JS API or replacement compiler. This independent probe is NOT the
cumulative HTML path, not a supplied production value and not page acceptance.
It includes locked mini_racer_v8.cc UNCHANGED and links existing locked libv8-node
static library, never libruby. Native host exposes exactly original logger paths,
actual v8_attach/eval/low-memory/call_await('emberVersion')/State disposal. Real
separate worker plus15s watchdog, original default multithread mode only (reject
configured single-threaded profile rather than forcing it). Source-declared
callbacks execute stderr-only; no JS host filesystem/process/network/PG API.

Compile artifacts only in newly owned fidelity/build directory, CPU0-3/max4;
no source/compiler/helper-tree/protected edits or extra persistent service. Copy
verified existing bundle to a separately owned fixture, identity/path/uid/nlink
checked before VM starts. Dispose original State/isolate, join worker, dispose
platform and verify own OS thread count returns to baseline on success/error.
Standalone process exit also reclaims process-global VM resources. No build
of AssetProcessor or node/pnpm child, no original Rails HTML, no PG at all.
Unit error/timeout fixtures must be explicitly separate and never production
inputs. Failure remains failure; no relaxed types/security/source checks. This
is independent application/cache-runtime work, NOT replay of the archived
provider-refused compiler operation; compiler sources/build remain untouched.

Native probe first REFUSED before compilation: actual default configuration has
mini_racer_single_threaded:true. No false multithread assumption is accepted.
The earlier original inspection omitted the source-specific platform flag API
and is therefore NOT the faithful configured-platform proof (preserve old file/
claim as failed profile; fresh evidence required). Revised source inspection
calls real MiniRacer::Platform.set_flags!(:single_threaded) ONLY when actual
configuration says so; this is matching production, NOT a forced sync/test mode
or a Rails initializer/declaration campaign. Native bridge supports the original
v8_single_threaded_enter/dispose State lifetime, still on the original separate
native worker; no source async cache Scheduler flag is touched. Exact original
flag string is passed only for that real enabled configuration; false preserves
original no-flag default. No default override to make the experiment pass.

## Compiler-version cumulative capability effect classification BEFORE execution (07:34)

Bounded native V8 component now actually compiles AND RUNS under Spinel through
Fiddle, using original locked MiniRacer C++/libv8, real configured single-thread
platform API, separate retained worker, actual repeated call_await and original
logger/GC callbacks. Exception/logger/15s watchdog and OS-thread cleanup controls
pass; no Ruby linkage/child or endpoints. This is a component, NOT request/page.
Next integration preserves context until scope cleanup (no fabricated booted flag,
one-shot-dispose shortcut, or reading original result as production input).

At actual import-map partial, original nonce helper executes BEFORE actual theme
compiler dependency. Nonce is genuine random request/header state, raw retained;
comparison alone may normalize the validated random nonce exactly like request ID,
never runtime/template output or security behavior. Registry comes from original
Discourse.plugins under LOAD_PLUGINS=0, not a supplied empty asset vector. Native
folds only source-proven no-plugin loops after checking that actual registry.

Fourth fixed cache key is source Theme.cache ('theme:compiler:' plus original
AssetProcessor::BASE_COMPILER_VERSION declaration). ONLY compiler_version String
entry is admitted, through same owned manager/backend/worker/lifecycle. Its cold
block is original Theme.compiler_version dependency construction and SHA1 over
actual global configuration/hostname + genuinely executed V8 emberVersion. No
observed version/digest is supplied to request/cache. Actual class registration,
subscription, queued job/pub/callback/server value/hits and cleanup remain checked.

VM source dependencies+existing cached bundle are materialized freshly per runtime
in an independently owned source-cache fixture; owner metadata+all file hashes
and compiled-library identity are checked at use. Parent/Valkey live ownership
reuses existing lease before VM dispatch. Actual real VM mode comes from provider.
Native platform driver uses Ruby-free original engine bridge; SAME CRuby platform
driver executes original MiniRacer APIs (only platform-driver file differs, like
PG driver), isolated-original methods remain a third process. Retain actual
context until ensure cleanup; external AssetProcessor build remains refused.

Theme extra_js array cache/baking is NOT admitted by this String-only capability:
original js_asset_info key construction reaches original compiler_version first,
then its get_set_cache must refuse array/bake acquisition BEFORE block/PG dispatch.
No [] asset response, false warm theme state, skipped applicable bake or permission
barrier claim. That next implementation gap is separate from later prohibited
stylesheet/Wizard writes. No full original Rails HTML/new PG authority/services.

## Real cumulative import-map/compiler acquisition checkpoint (Nov8 08:14)

`build/probe-portable-security-20261108-080547/evidence.json`:
**PASS_IMPORTMAP_PREFIX_REAL_V8_COMPILER_VERSION_CACHE**. Fresh native compile AND
RUN; SAME CRuby (same application + actual MiniRacer platform driver) and THIRD
isolated original full ERB/import-map/theme compiler methods match. This is now
actual application-layout -> plugin_js partial -> genuine CSP nonce -> genuine
Theme.compiler_version with actual V8 execution and exact cache publication. It
still REFUSES before extra_js array cache/bake callback; no fake JS asset vector,
returned import map, full layout/HTML200/browser/page/019 acceptance.

Fourth cache real local/server compiler_version maps agree across all runtimes;
original dependency construction uses real configuration/host + actual engine
emberVersion. The observed digest is output, never supplied input. Actual V8 is
retained through both requests and disposed/joined at success/error cleanup; native
loads the original C++/libv8 bridge through Fiddle in the SAME ELF, no Ruby child,
network endpoint or external AssetProcessor build. Original package .cc/.h and
static library verified against locked archives; additional current component
`native-asset-vm-20261108-519727-jfxpw8` also verifies every installed V8 header.
Both modes respect real configuration (current single-threaded:true); source GC
post-call and idle callbacks remain, logger callbacks actually execute in controls.
Ruby-free component tests include retained repeat calls, actual logger, exception,
15s watchdog, own OS threads1->1, disposal/join and source-fixture cleanup.

Source fixture metadata/artifacts contain ONLY copied dependency/cache SOURCE
bytes, never original output/version/PG payload. Each runtime source fixture is
new, owner/hash/library checked, removed in ensure; ordinary cache fixtures remain
independent. All inherited20cache+10request+6body+8color controls and7ingress/process
pass, plus4NEW native/shared compiler-publication/VM-source-ownership controls.
No relevant guard/assertion is weakened. Random nonce is actual request/header
state with25alnum schema and bound output checks; only Python comparison normalizes
that one validated nondeterministic field, raw stdout/prefixes preserved unchanged.

Preserved failures include073410 missing typed blank binding,073440 unreachable
array/bake block polluting strict String cache type,074320 generic nested yield
forwarding returning polymorphic type (failed compile),075141 missing original
view.response protocol. Changed diagnosis: specialize the known original compiler
block at its concrete typed cache call site; raw original keeps unmodified method.
Unacquired array/bake callback is explicit raising boundary in native projection,
full original remains as THIRD reference and is also UNENTERED. No widened types,
compiler source edit or weakened C diagnostics. Separate raw-original diagnostic
passes before080547 fresh full cumulative proof. Failed canonical runs unchanged.

Next indispensable operation is original Theme extra_js array-valued cache/bake
lifecycle (including real Marshal publication and readonly data/cold predicates),
not permission to execute forbidden PG writes. Current source-backed inspection
shows theme-1 extra_js empty; do not infer a PG barrier from another theme. Need
proper typed Array cache capability/reuse of guarded fixture, not injected [] or
skipped real callback/publication. Later stylesheet/Wizard PG writes still forbidden.

## Next Array-cache lifecycle classification / typed experiment boundary (08:24)

Original Manager#set marshals Set/Hash/Array, Base64.encode64(Marshal.dump(value)),
marshalled:true; same source publication-before-local-update. Exact source Array/
Symbol-Hash encodings and round trips now match native/original in explicit UNIT
vectors (test/theme_cache_marshal_unit.rb). These values are NEVER production data,
cache warmers or a completed import map. Existing live transport still rejects
marshalled payloads: no Array publication has been enabled by this unit proof.

A safe next candidate must preserve strong String return contracts for category/
icon/color/compiler callers, add a separately typed Array-of-asset-record getter
on the SAME Theme cache instance, keep real Scheduler/Manager/Marshal publication,
validate ONLY source-generated extra_js key and source-computed outgoing bytes
before dispatch, and retain own-origin/version/namespace/fixture ownership. No
generic messaging framework, arbitrary Marshal object loader or weakened types.
Refuse foreign/unobserved payloads BEFORE callback/deserialization. Runtime actual
Array (possibly empty) must come from real JavascriptCache association SELECTs,
not an injected []. Reads of ThemeField rebake conditions must be materialized;
any applicable ensure_baked!/update_javascript_cache! path must refuse BEFORE PG
write/unknown compiler effects. No preflight against theme-2 or stale inspection
snapshot can establish theme-1 safety; reacquire real state for every runtime.

This is implementation work, not a request for new permission. Existing authority
is cache/log only; complete bake/stylesheet/Wizard PG effects remain prohibited.
Bounded attempt31/400turn cap still applies. Keep90ff530 and its passing String
capability unchanged until a separate typed Array experiment actually passes.

## Actual Theme Array cache checkpoint (Nov8 09:27)

`build/probe-portable-security-20261108-091817/evidence.json`:
**PASS_SCOPED_THEME_ARRAY_CACHE_BEFORE_ASSET_GRAPH**. Fresh native compile AND RUN,
SAME-lowered CRuby and isolated original full Theme.js_asset_info callback agree.
Actual source ThemeField extra_js target/changed-compiler relation is reacquired,
rebake set materialized; actual JavascriptCache SELECT and last-per-theme/requested
order conversion yield current Array. The observed [] is real output of those
queries, NEVER injected/preloaded or a fake theme response. Real source Marshal
bytes/marshalled:true publication, deferred queue/worker, Manager callback, local
update/server backlog and warm no-recompute all execute on SAME owned Theme cache
instance alongside compiler_version String. Typed String sites are not widened;
Array getter has an explicit Array-of-asset-hash value union plus exact key/record/
field type checks. No new bus/framework, endpoint, service, opaque object loader,
PG write or altered original/reference source.

Only source-generated Theme extra_js key is admitted. Lease registers encoded
bytes from the genuinely computed, schema-checked Array before actual Manager#set;
wire/inbound must exactly match those bytes+owned origin/version/namespace. Only
then may telemetry decode that owned payload. Missing marshal flag cannot degrade
the array into a String. No arbitrary/unobserved Marshal object is deserialized.
8NEW native/shared controls reject tampered wire, missing marshal flag, omitted
Array publication and effective rebake-required guard BEFORE PG effect dispatch.
All inherited20cache+10request+6body+8color+4compiler controls and7ingress/process
remain passing (compiler controls explicitly reapplied to Array stage). Normal and
error exits clean Valkey/source/VM fixtures and actual threads; native remains one
ELF,2readonlyPG+4ownedcache, no Ruby child. Actual remaining import-map asset graph
is an explicit refusal after acquiring Array, not completed import map/layout/page.

Source-equivalent adaptations: same-instance separate typed Array getter; validated
String key materialized as String before monitor closure; structured warm-hit
if/else avoids nonlocal-return type/control ambiguity while preserving value.
Native candidate materializes readonly rebake relation and refuses nonempty set
with ArgumentError before ensure_baked!/update_javascript_cache!; original full
callback executes unchanged on the admitted actually empty rebake profile. Normal
readonly transaction still executes. JavascriptCache source URL/read fields only;
no write callbacks admitted. Source targets are parsed from original Enum keyword
declaration, not guessed numeric IDs. Original relation .index_by binds a genuinely
materialized array, not invented cache rows. Strong Array RBS+runtime schema, no
untyped weakening or compiler edits. Committed String-only gates remain unchanged.

Failures retained:083454 missing existing asset-host RBS read contract;083520 strict
C key dispatch mismatch;084258 compiled+ran actual Array publication but failed
warm-return control;085025 native/shared passes, original dependency ordering
failed; separate corrected original diagnostic passes.090820 full scope passes;
091817 explicitly reapplies inherited compiler controls and self-contained VM
artifact build fallback. One negative first returned a rendering boundary (normal
refusal) instead of failing nonzero; fixed out-of-profile rebake guard raises
ArgumentError, then all controls pass. No failed canonical run is relabelled.

Reproduce `make -C fidelity verify-theme-array-cache`; standalone Marshal unit
vectors remain clearly labelled and never feed the request. Next genuine path is
EmberAssets build-status/manifest/import_map lifecycle + actual Propshaft paths to
complete the real import-map tag, NOT missing permission for already owned cache.
Only bounded400turn continuation remains; approaching its cap, reserve final audit/
clean checkpoint rather than start unverified compiler or PG work. Full019/HTML200/
layout/browser/page remain FALSE; later stylesheet/Wizard PG writes prohibited.

## Final ownership hardening / integrity regressions (Nov8 09:57)

Source-reviewed final guard changes reject nil/unknown cache registration or the
spurious '_set' descriptor when no Theme namespace has been acquired; VM bundle
must be one of the explicitly verified owned source members, not traversal,
absolute or unlisted input. Full native425.981s compile AND RUN + three-way Array
proof/control suite passes at094443. Explicit separate native/CRuby UNIT guards
also reject3 registration/descriptor cases and4 VM-member cases BEFORE fixture/
source read/VM dispatch; they are not request or production payloads.

All8 existing source asset/CSP/nonce/preload Make targets PASS again; cumulative
readonly095449 PASS. Both immutable trees reverified ALL27,435blobs each including
symlinks, canonical aggregate unchanged1e1d4bbf63d2888ac507550b8c3ed0fbb3026d123b1853bef4b295194869d9c0.
All compat/progressive/source composition bytes unchanged vs Recovery30. Compiler/
original/minimal trees clean; no helpers/children created. Native final audit:
1ELF execve,2PG5499+4ownedcache connections,117 observed SELECT/SHOW/readonly
transaction-control SQL statements, no shared6399 or PG write verb. ALL owned
cache and VM-source cleanup records true. Nov7 auth SHA unchanged, usage CONSUMED,
exactly1failed original HTML invocation and prior cleanup verified. Historical
provider refusal archived/unresolved, no restricted operation replay/reroute.
No second Rails HTML, privatePG, snapshots/dump/restore, write prompts/notification,
protected-root/harness/ticket/docs/ledger edit, publicpush/PR/deploy/service/helper.

Fresh quota45% (<75soft/80hard); task+all retained related roots and conservative
/tmp task/spinel/roundhouse/discourse entries119784828928bytes (~111.56GiB)<150cap.
MainCPU0-3/max4,aggregate8. Deadline remains Nov8 16:27:43Sydney/168h unchanged.
Attempt31 fixed400turn allowance nearing cap; final coherent checkpoint/audit is
reserved, not claiming missing implementation is missing permission or full019
completion. Current next indispensable capability is source EmberAssets development
build-status/manifest/request-cache + real Propshaft resolution for actual serving
asset root (genuine built frontend exists, original root lacks dist manifest).
No unit graph/host/config may be substituted; inspect/contain that exact lifecycle
before execution. Later stylesheet/Wizard PG writes remain prohibited separately.

## Next-step write-free EmberAssets inspection BEFORE execution (10:07)

Within remaining fixed-turn reserve, inspect ONLY original full EmberAssets class
with actual locked ActiveSupport CurrentAttributes, real development environment
(the SAME admitted request profile), original build-status/manifest/cache methods.
Two readonly source roots are inspected: original has missing dist manifest; genuine
previously built immutable-source frontend tree has its real manifest. This does
NOT configure a request, substitute a serving root, supply imports or complete an
import map. Both source trees remain untouched. No watch!, Listen, file-change bus,
node/pnpm/build invocation, PG, network, persistent service or V8 needed. Missing
build status/manifest follows original BuildError logic, no fabricated fallback.
Actual cold/warm CurrentAttributes cache executes; reset on success/error, thread
count returned to baseline. Only new inspection log artifact is written. These
observations are never fed to application/cache/runtime. Native asset lifecycle
integration remains next work after bounded attempt31, not missing permission.

## Committed verification / bounded handoff (Nov8 10:09)

Committed implementation **c83ccbf** recompiled AND RAN at
`build/probe-portable-security-20261108-095719/evidence.json` (421.414s native
compile): PASS_SCOPED_THEME_ARRAY_CACHE_BEFORE_ASSET_GRAPH, same actual20+2rows/
35972+4327bytes, all inherited/new controls and all fixture cleanups pass.
Source-audit-final.json points to this committed run; previous successful and
failed runs remain preserved. No active owned probe/compiler/Valkey/VM-source
child remains. No agent child was spawned. Fidelity code checkpoint clean.

Additional ORIGINAL-only full EmberAssets inspection now passes. Actual locked
ActiveSupport CurrentAttributes and Rails EnvironmentInquirer run unchanged class
methods: original root raises real missing-manifest BuildError; existing genuine
frontend tree reads SHA256353d6bcfe09088e3e998274f76ef246b174bb989709ad327f260a976064b4b1e,
53import entries/14script chunk entry groups, actual cold/warm manifest/cache/
chunk objects retained, reset/thread cleanup. No watch/listener/build/PG/bus called.
Initial inspection failures are preserved: StringInquirer did not implement Rails
local? semantics and wrongly bypassed missing-manifest BuildError. Identity facts
exposed the wrong profile; replacing it with actual EnvironmentInquirer fixes the
cause without changing flags, faking output or weakening lifecycle assertions.
This inspection remains NOT native/request acquisition or production inputs.

The next indispensable IMPLEMENTATION is native/same-lowered real EmberAssets
serving-root/build-status/manifest/CurrentAttributes lifetime + actual Propshaft
load-path/URL resolution, then finish import_map. Existing pure graph/vector
proofs do not replace it. A genuine previous build is available but must be
source-faithfully acquired/bound, not injected into a controller/unit host. Later
stylesheet/Wizard PG writes remain prohibited; cache acquisitions never authorize
them. Do not restart initializer/declaration/template-order campaigns or replay
historical provider refusal. The fixed400turn attempt31 is now in final audit/
handoff reserve; do not claim new permission missing, deadline/quota exhaustion,
HTML200, browser/page acceptance or019 completion. Same next source/WIP/checkpoints,
no new services/helpers/prompts or authority reuse are needed for asset inspection.
