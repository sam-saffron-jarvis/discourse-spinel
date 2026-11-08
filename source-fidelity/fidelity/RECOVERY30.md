# Recovery30 — executed original-order list template prefix, not a body/page

SAME019 / safe session20261107-085321-f206496e99b8e410 / same source trees.
Recovery29 Fidelity75492e7 and Roundhousee37a17673 are preserved. Native JSON150855,
HTML request-stage000503, cumulative baseline002002 and the unaccepted legacy
initializer/declaration failure002030 remain evidence, not retried or relabelled.
Full019/originalHTML200/nativeHTML/browser/page acceptance remain FALSE.

## Actual order, not a render-level assumption

Pinned ActionView8.1.4 `lib/action_view/renderer/template_renderer.rb`:

1. `render_template` calls `render_with_layout`.
2. `render_with_layout` finds the layout BEFORE executing the body.
3. `view.view_flow.set(:layout, yield(layout))` evaluates the view-flow receiver,
   then executes the body through `yield(layout)` BEFORE calling `set`.
4. Only a successful body return permits `layout.render`.

Consequently the application layout need not execute before the list template.
The supported anonymous desktop request genuinely selects application layout;
original `include_crawler_content?` evaluates true from acquired request/settings.
No crawler/header/settings flag was forced. The core/no-plugin outlet returns
empty by its real GlobalSetting guard. This is not omission of an applicable
plugin branch. Original `/latest` has no category/tag controller assignments;
both are checked nil before the two structurally unreachable template branches
are lowered away. Authenticated/mobile/other layouts, categorized/tagged and
unhandled alternative template paths refuse rather than silently render less.

## Implementation and exact execution scope

`make verify-list-template-prefix` runs tools/probe_list_template_stage.py. It
extends the existing real HTML controller/query/serializer/preloader acquisition,
not JSON admission. The continuation runs inside the active controller/request
scopes, after actual original derived-list storage, at the former pre-render
refusal. No supplied topic/Site/settings/preloader payload is production input.

`tools/generate_list_template_prefix.rb` verifies original source against
96ce8d44401a8a568ecc71561c26dca8ec6bfeb8 and compiles actual list/list.erb using
ActionView's Erubi handler. It cuts the native prefix immediately before the
append of `t.category.url` (list/list.erb:66; compiled-method append byte3742).
Open scopes are balanced with explicit refusing alternative exits, not claimed
as completed rendering. Exact original renderer methods retain body/layout
ordering. A checked, hash-verified two-file catalog implements only this scoped
lookup; it is NOT a general ActionView resolver or full Rails render stack.

The private prefix accumulator accepts ordinary String/Integer expressions and
uses existing ERB escaping. The application URL methods, layout selection,
uncategorized predicate, base URL protocol and anonymous helper branch derive
from original spans. An unreachable authenticated `:print` branch is specialized
behind an explicit anonymous guard, not replaced by a forced crawler result.
There are no compiler/runtime edits or general renderer/cache subsystem changes.

A THIRD fresh CRuby process executes the FULL original Erubi-compiled template
with actual ActionView::OutputBuffer, untouched original renderer sequence and
untouched original crawler/outlet helper methods. Delegating Topic/Category
wrappers read freshly acquired real records. Original Category#url itself reaches
a refusal-only cache capability and validates its real String key; no pretend
cache hit/miss or URL is returned. The original full template naturally stops at
the same point. It is an isolated original-template comparison, NOT another
original Rails HTML request. No template remainder, layout, response or page is
represented as executed.

## Fresh executed evidence

**build/probe-portable-security-20261108-010430/evidence.json**:
PASS_SOURCE_LIST_TEMPLATE_PREFIX_BEFORE_CACHE_CAPABILITY.

- Fresh native compile337.322s; actual native/shared CRuby and isolated-original
  executions pass. Same emitted Ruby differs only in runtime/pg_driver.rb.
- Actual newly queried lists have20topics and2paged topics. Prefixes are893 and
  906bytes, respectively, including translations, real first topic URL/title,
  integer position and the literal opening category-link href. IDs5/category4
  and28/category5 are observations, not fixed inputs. Complete prefixes and
  typed records agree across all three processes.
- Prefix SHA256s7090244a611a2ca993d1e53b75b3b50fad7110a149806890c5120e53a59c9395
  and2cf5e114b5d12e9cb53dee49508926a30256104cccf4823a4b8f2ffd44ee0df8.
- Executed event order: template lookup -> layout lookup -> view-flow receiver
  -> body template -> category-cache capability refusal. Neither view-flow set
  nor layout.render nor completed body/response runs.
- Six new negative executions: omit genuine title, unescaped accumulator, and
  layout-before-body, each under native and shared CRuby. All fail nonzero with
  expected errors; the escaping unit string stays explicitly separate from the
  production output. Ten inherited request-stage negatives and7ingress refusals
  per process also pass. Owned-fixture cleanup passes for all20runner cases.
- Native trace: one ELF execve, two PG5499 connections and one separately owned
  disposable cache connection; no Ruby child/shared6399 connection.72observed
  native SQL statements, both PG paths readonly ON, zero native cache effects.
  Request/controller/locale/profiler/query-session/interlock/pool cleanup passes
  at the new refusal boundary, not merely at the former pre-render boundary.
- template-prefix-proof.json records original file/method span hashes and byte
  ranges, full compiled-template hash, native-prefix hash, exact renderer-method
  hash, ActionView8.1.4 package/member hashes, MessageBus5.0.0 distributed-cache
  package/member hashes, supported pruning, ordering and false acceptance flags.

Fresh cumulative readonly `make verify`: **build/verify-20261108-011210 PASS**
(isolated original-scope AR/PG, NOT full TopicQuery or HTML). After implementation
commit **b94a022**, **build/verify-20261108-011713 PASS** reverified the committed
source and owned-fixture cleanup (build/recovery30/committed-readonly-baseline.log).
Its existing actual
original declaration-scope oracle uses only the owned cache/log fixture; it is
not an original Rails HTML invocation. All prior baselines remain preserved.

## Preserved failures and recoverable fixes

- build/probe-portable-security-20261108-004304: native C compilation failure,
  boxed/integer dispatch involving unreachable authenticated `:print`. A bounded
  syntax diagnostic and source-proven anonymous specialization fixed this without
  touching Spinel or the archived provider-refused operation.
- build/probe-portable-security-20261108-005111: native/shared prefix executed,
  but original comparison initially failed on whole-ActionView I18n loading.
  Loading only real OutputBuffer dependencies avoids the conflicting full
  framework bootstrap. Original Category class-variable lexical ownership was
  then corrected in the comparison adapter. Diagnostic logs and failure states
  are preserved under build/recovery30;005111 is NOT relabelled final acceptance.
  Its later diagnostic comparison passed;010430 is the fresh final full run.

## Exact remaining effect boundary — no invented permission or cache state

First applicable missing dependency is list/list.erb:66 -> Category#url at
app/models/category.rb:1131-1133 -> `@@url_cache.defer_get_set(id.to_s)`.
The actual cache is initialized at category.rb:1125 using DistributedCache.new.
MessageBus5.0.0 DistributedCache#initialize invokes Manager#ensure_subscribe!,
which calls MessageBus.subscribe('/distributed_hash'), then registers the cache.
On a miss, Discourse DistributedCache#defer_get_set computes the URL and invokes
`Scheduler::Defer.later('category_url_set')`; its real async lifecycle starts
queue/thread/reactor work, and the deferred cache assignment calls manager.set
and MessageBus.publish with queue_in_memory:true. These are effects, not a pure
string helper. The current request profile has no acquired, guarded implementation
of that manager/subscription/deferred publication lifecycle. We do NOT claim to
have initialized that cache, observed a hit/miss, or dispatched any of it.

The next concrete action is acquiring/executing that original category-cache
capability with verified owned backend/namespace, actual subscription/defer/
publication semantics and thread/queue/endpoint cleanup. It must not run the
unreviewed default MessageBus against shared services, substitute a warm cache,
force synchronous/test mode, suppress publication, or just return the pure URL.
Existing disposable cache/log authority is conditional, not blanket authority
for external jobs/messages: a demonstrably contained cache-only implementation
might fit it, but that containment/lifecycle has not been established here.
This is a precise unadmitted effect capability, NOT a claim that all cache writes
are inherently forbidden and NOT a request for another PG approval. There is no
remaining legitimate write-free continuation past this dependency in the acquired
profile without inventing cache state or skipping the required call. Generic
MessageBus/Scheduler expansion and unguarded dispatch were not substituted for
the bounded template experiment. Later real layout stylesheet and cold Site/
Wizard writes remain independently prohibited; their old permission is consumed.

## Integrity/resources

build/recovery30/source-audit-final.json verifies all27,435blobs in BOTH original
checkout and genuine frontend source copy, including symlinks, still match pin;
canonical aggregate1e1d4bbf63d2888ac507550b8c3ed0fbb3026d123b1853bef4b295194869d9c0.
All previously tracked tools/test/compat bytes (including Recovery28 CSP/assets)
are unchanged. Spinela1a1bea71/Roundhousee37a17673/minimalc975ee1 remain unchanged.
Consumed approval SHA45ef2a1be8bc05a4ebade3ebd7948218049df732bdabcee50bd4260120fc4ca7,
one failed original HTML invocation and verified cleanup remain unchanged.
No privatePG/snapshot/dump/restore/second Rails HTML/native-or-compat PG writes,
permission prompts, helpers/revivals/helper-tree edits, protected coordinator
edits, publication/deploy/Hub/demo/new persistent service or refusal replay.

Quota41%/75soft/80hard; retained task plus related trees107.34GiB/150cap at01:14;
mainCPU0-3/max4, aggregate8; unchanged Nov8 16:27:43Sydney/168hdeadline.
This is newly EXECUTED source-faithful request/template-prefix progress. It is
neither a completed list body nor HTML200/page/browser/full019 acceptance.
