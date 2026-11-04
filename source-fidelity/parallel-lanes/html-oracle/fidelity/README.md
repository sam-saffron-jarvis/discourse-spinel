# Discourse source-fidelity /latest compatibility lane

Sam approved this strategy on November2: original Discourse application bodies
remain unchanged except individually evidenced unsupported-Ruby transformations.
The parked `minimal/` implementation is a demo/reference, NOT this query engine.

## Ticket019: partial TopicQuery foundation — BLOCKED, NOT PASSED

`make verify-topic-query` adds a separately named, fail-closed probe of the
**original category-security expression**, original Guardian filter/allowed IDs,
and original anonymous identity/admin predicate. Complete source inputs and
selected expression/method bytes are hash checked before/after. See
`COMPATIBILITY-TOPIC-QUERY.json` for the exact source cut and remaining closure.

The reusable runtime now preserves references through the relevant merge, builds
supported direct belongs_to filtering joins from declaration metadata, and quotes
positional array binds as SQL lists. Owning emitted and native framework tests
use isolated SQLite memory. No replacement Discourse query/permission code exists.

**019 does not pass.** Native compilation keeps and refuses the original dynamic
`SiteSetting.suppress_secured_categories_from_admin` call. A separate bounded
experiment with the complete original settings files reports unadmitted typed
receiver/callable/storage obligations at the original `define_singleton_method`
event; no fake getter/default is installed.
The partial anonymous expression executes under CRuby and actual full Rails,
including real restricted/NULL/dangling-category SELECT-only cases. Strict
comparison now agrees, including derived case107 SQL NULL visibility. The fix
records read-shape nullability separately from physical constraints; it does NOT
make the database schema nullable. Owning emitted/native scalar regressions also
prove that SQLite-memory physical NOT NULL constraints still reject NULL writes.
Actual category-filter omission is rejected by strict record and ID controls.

An actual-Rails cold-getter experiment reaches original refresh!, theme-cache
DEL operations and Site.clear_anon_cache!'s MessageBus cache-sequence publication,
plus original logging effects on the owned oracle fixture. **Nov3 23:12 explicit
approval** in `../run/NATIVE_COMPAT_SANDBOX_AUTHORIZATION.json` also permits real
native/compat cache/logging effects in separately owned guarded disposable
Valkey fixtures. This supersedes earlier oracle-only containment ONLY for that
scope: PG/shared Valkey stay protected, no shared cache warming/fake responses,
and cleanup/endpoint negatives remain mandatory. No native/compat cache-service
writes have yet been performed; callbacks/publication were not suppressed.
Original SiteSetting bootstrap and native User/eager-hydration remain unproved.

Full Rails alone also observes real non-admin/admin identities, the live effective
setting and applicable plugin chain, without callbacks/settings being disabled.
That is **not native/compat authenticated-branch coverage**. Compat still filters
through a parent join and batch-preloads categories in two queries, versus Rails'
one joined eager-hydration query; this difference is recorded, not claimed away.
There is no original019 native ELF/PG trace or native negative control because
native compilation refuses. The target remains nonzero on these incomplete
contracts; a future compile-only success also cannot accidentally pass it.

The oracle uses the same owned disposable Valkey fixture and endpoint/read-only
PG guards as018. All actual effects and child cleanup are recorded on both paths.
Original `discourse/`, parked `minimal/` and the running demo remain untouched.

## Nov4 source-backed runtime-definition checkpoint (not019 acceptance)

A reusable typed runtime event family now supports genuinely runtime-derived
String/Symbol names, explicit method receivers, live lexical captures, aliases,
Method snapshots/identity, visibility and actual singleton callbacks. Six native
owning/full-framework controls pass; generated runtime and lifted bodies are
closed, without stored-Proc self rebinding or eager owner getter installation.

`python3 tools/verify_global_setting_register.py --cache` executes byte-exact
original GlobalSetting `register`, `add_default`, `configure!`, `load_defaults`,
its original accessor and complete Base/ENV/File/Blank providers. The original
defaults resource is packaged verbatim, read and parsed at runtime. Twelve
original/lowered/native cases prove cached false/zero/nil, real config-file and
ENV semantics, live register replacement, and invalid cache-name errors. Config
input files are created after ELF compilation. All three original lifted event
bodies are also checked for closed types. This selected source closure is not
full GlobalSetting/Rails/SiteSetting/plugin/cache-service boot or security.

The existing `verify-settings-pure` additionally parses the **entire original
`config/site_settings.yml`**, not just toy YAML. All1110 records, observed default
value types and metadata (including nested key classes) compare across original/lowered/native;
actual file reads are traced, network rejected and native child execution rejected. This proves
resource/parser readiness, **not** that the yielded records become settings.

Remaining source boundary: actual model `extend`/`load_settings` events remain
carried, but `SiteSettingExtension#setup_methods` is an instance-owned module
producer, not a plain class-root family. Its actual SSE1143 getter needs an
optional-argument callable ABI, method-return frames and closed source-derived
current/theme/plugin/UpcomingChanges/provider contracts; many body nodes still
have unknown types. Ordinary computed names now work, so unsupported warnings
also report these remaining obligations without suppressing the original
rejection. The diagnostic now carries21 complete original Ruby files plus3 resources
(406327bytes), including whole pinned UpcomingChanges, Discourse and
ThemeSiteSetting dependencies, plus Plugin::Metadata and its original official-plugin
resource. Output is still NEVER executed.
Adding optional-argument syntax alone would not close or license the getter;
missing applicable dependencies must not be stubbed or pruned. Native method
replacement should not be assumed from names in nested helper classes: the
lexically correct named-method overlap audit finds no current YAML/outer-source
collision. Global overrides/default-locale hook remain runtime inputs whose
actual paths must be proven when selected.

## Existing isolated original-scope proof (ticket018)

`make verify` freshly compiles and executes an **AST-selected declaration slice**
of the original `Topic.listable_topics` and `.visible`, original `Trashable`
default scope, original `belongs_to :category`, and `Archetype.private_message`.
The same emitted Ruby runs under native Spinel and Roundhouse's CRuby runtime,
except the existing platform PG driver shim. Both match an actual separate
Discourse/Rails8.1.4 oracle loading the unchanged complete models on the same PG.

This is **not full-model native boot, original TopicQuery#list_latest, serializers,
controller, HTML or browser /latest completion**. `COMPATIBILITY.json` records the
precise dependency cut and remaining closure. Coordinator acceptance is separate.

The proof distinguishes:

- Five nonempty **live** topic rows, typed scalar/NULL values, microsecond times,
  category identity/name, lazy composition, batched preload and memoization.
- Ten explicitly labelled SELECT-only **derived test cases**, using a real seed
  row plus varied archetype, visibility, deletion, nullable values and category
  FKs. The original scope bodies select five cases. No PG rows/schema are written.
- An actual second execution of the native ELF with a deliberately wrong TEST
  consumer omitting `.visible`: comparison with the real oracle must reject it.
  Original declarations are unchanged. A boolean→integer type mutation must also
  be detected by the strict comparator.
- Bound quote/question-mark/backslash inputs, limit-fork immutability, NULL binds,
  missing/dangling associations, and RecordNotFound/ArgumentError/StatementInvalid.

## Real oracle isolation and effects

Nov3 authorization in `../run/ORACLE_SANDBOX_AUTHORIZATION.json` permits a single
short-lived, disposable writable Valkey child for real Rails cache/logging
startup effects. Shared Valkey6399 remains protected. No fake Redis, source edits,
callback/plugin stubs or disabling of settings/profiling is used.

`tools/oracle_sandbox.py` starts its owned child on an unused127.0.0.1 port distinct
from5499/6399, no persistence/daemon/service registration. It verifies PING, server
PID, bind/port and persistence config. Negative tests run **before Rails boot**.
Ruby guards reject every Redis client whose actual config is not that owned
endpoint, at configuration, connection and dispatch, including pipelines. Real
cache invalidations and Logster pipelines run and successful replies/callers are
recorded. Cleanup is required on success, errors and interruption; only owned
children are signalled.

PG stays on127.0.0.1:5499/discourse_development, read-only in all paths. Native and
compat use the shared `DATABASE_READONLY=1` per-physical-connection policy, with
pool/reopen regressions. The real oracle guards constructor aliases, startup
options, prepared SQL and session overrides, and records actual server/read-only
checks. Other network endpoints fail closed. The original read-only libvips
version check may use only its proven private original worker child/socket;
that child is explicitly cleaned up, not a shared/external service or new writable
fixture. Unknown Unix sockets remain rejected. Alias-based MiniProfiler hooks
remain enabled and observed; guard instrumentation must not recurse or omit them.

## Run

From the task root:

```sh
source harness/env.sh
export CARGO_BUILD_JOBS=8 BUNDLE_JOBS=8
make -C fidelity verify
python3 -m unittest discover -s fidelity/test -p 'test_*.py' -v
```

Requires task Ruby/bundle, PostgreSQL, `valkey-server`, `strace`, native Spinel,
and an existing spinel-pg0.2.0 checkout via `SPINEL_PG_DIR` (default: user's Spin
cache). Each invocation creates a new ignored private `build/verify-*` directory:
source locks and original AST spans, live catalog/schema, labelled fixture SQL,
macro map, emitted Ruby hashes, compile logs, ELF hash, exec/connect trace,
three-way observations, detected negative controls, actual oracle source/version
metadata, endpoint negative tests, real effect replies and fixture/helper cleanup.
Native runs before the oracle and cannot consume oracle records or spawn Ruby.

Complete files under `source/discourse/` stay byte-identical to pinned upstream
96ce8d44401a8a568ecc71561c26dca8ec6bfeb8. Projections explicitly omit other bodies
for this isolated slice; no complete native model/callback/plugin coverage is
claimed. Framework semantics belong in Roundhouse's shared runtime/lowering,
PostgreSQL primitives in its PG runtime, and demonstrated compiler defects only
in Spinel. Unsupported paths must fail, never return empty successful output.
Do not revive whole-app33MB/5k-file compilation or deploy compatibility probes.

## Pure settings dependencies (not ticket019 acceptance)

`make verify-settings-pure` projects the original `SiteSettings::YamlLoader`
(all its methods) and the pure initialization/load_setting/all_clean/membership
subset of `DefaultsProvider`, retaining byte offsets, private visibility and
constant declarations. Complete original files remain hash-locked; selected
bytes and all unselected whitespace are audited before and after execution.

Freshly emitted **identical Ruby** runs under native Spinel and CRuby, with an
unlowered original-projection reference using the actual bundled
ActiveSupport/Psych libraries. This is a pure library reference, **not a Rails
application boot**. Synthetic YAML fixtures are never production settings
snapshots. Tests cover false/zero/empty/nil, aliases, original category/value/
metadata yield, recursive key conversion, missing-default and validator-conflict
errors, locale overrides/fallback, copied defaults and membership. A deliberately
wrong native expectation must fail. All three execution traces must show **zero
network connections**; no PG or Valkey fixtures are started or used.

Roundhouse also expands literal `sub(...).to_sym` declaration names while
retaining scalar captures and optional arguments. Mutable String results are
not constant-folded. A narrowly guarded ordinary app-module `extend` now
contributes declaration methods to a plain class's macro lookup: one class
opening with no superclass/mixins/state or unrelated load-time observations,
one otherwise-unused top-level stateless module, and immutable captures only.
Installation order is retained; class/module callbacks, core-class reopens,
lexical state, other uses, mutable captures and prematurely relocated runtime
evaluation remain refused. CRuby retains original replay for those cases,
including a pinned pre-declaration reader observation. This does **not** cover
original stateful model extension.
Recursive destructive key conversion lives in the shared
runtime/lowering, with transitive wrapper/alias key-evidence invalidation.
Custom key conversion remains an explicit NotImplementedError boundary. Native
rekeying of nested, statically String-keyed literal containers is still a Spinel
layout limitation and explicitly raises TypeError; the YAML-produced open
container path is separately executed. No general native Hash support claim is
made from these tests.

**Still unproved:** full original dynamic settings declaration, runtime getter,
production default/plugin/upcoming-change/provider/cache/User integration, and
original native TopicQuery security execution. The separate modifier target
below executes more original pure default-provider logic without claiming
production service initialization. Writable fixture
authority remains actual Rails oracle only. Native/compat cache writes remain
forbidden; the coordinator owns the separate scope question. This pure target
does not change or soften `verify-topic-query`.

## Pure modifier dependency (not production plugin proof)

`make verify-plugin-pure` executes original `register_modifier` / `apply_modifier`
with a **real original projected Plugin::Instance** constructor, `configurable?`
and `enabled?` body. No plugin predicate or callback implementation is stubbed.
The fresh fixture instance has no enabled-site setting; **configured and disabled
plugin branches remain unproved**. No production plugin registry is loaded,
replaced or suppressed. Registered modifier blocks are explicitly synthetic
in-memory test inputs.

Checks include unregistered identity, callback order, the original captured-length
iteration rule when a callback registers another callback, forwarded arguments,
mutated and replacement Hash results, Integer values and exception propagation.
Original `DefaultsProvider#all`, activation and deactivation methods then execute
through that real modifier dispatcher. A TEST consumer borrows the original
`upcoming_change_default_overrides` metadata method using the existing generic
`define_method(name, mod.instance_method(name))` expansion. Its body is not
hand-written; no `extend` event occurs, so no extended hook is suppressed. This
is **not a SiteSetting object or a value getter**. Synthetic metadata exercises
inactive/active/deactivated overrides, explicit opt-out, locale defaults,
modifier ordering and preservation of stored defaults.

The same emitted Ruby runs on CRuby/native against the unlowered byte-audited
original projection (whose TEST consumer performs the real unbound-method
borrow). Wrong native expectations must fail; all three traces show zero
network connections and native must spawn no child. No fixture test consumer
is imported by the strict TopicQuery security target.

The complete original plugin/registry/namespace files extended the source lock to
**25 files** at that step (**36** with the bounded settings dependency inventory
below). An original SiteSetting **class declaration only** is included for
analysis of the unexecuted configured-plugin branch; no getter is fabricated and
that model is **not loaded** by this pure consumer. Native compilation explicitly
warns that SiteSetting is unavailable if reached. The real original
`enabled_site_setting` API drives a configured-case negative control: native and
unlowered reference must both fail with SiteSetting NameError, not silently
return enabled. This is **not configured-plugin support**. Production plugin
startup/disabled branches, actual SiteSetting service initialization and its
native value getter remain unproved. It does not soften019.

This original integration exposed a reusable Hash bug: inferred String key
storage caused a typed Symbol modifier name to be rewritten as String. Plain
Hash reads/writes/fetch/delete/dig now preserve the original key identity;
proven request params retain indifferent normalization, including explicit
provenance across the view/controller bridge. Owning typed-key native/CRuby and
params/view/session regressions guard both contracts.

## Declaration capture/order prerequisite

The existing class-owned/inherited declaration evaluator now preserves String
**allocation** identity rather than interning captured values by equal text.
Aliases share one captured object; separate `Symbol#to_s` evaluations and loop
iterations remain separate mutable objects. Runtime captures carry explicit
`DeclarationStep { call, ordinal }` metadata: evaluation occurs once at the
calling declaration, not at the macro definer's source offset. Original
expression/block spans remain intact, including inherited foreign-file macros.

Owning regressions execute original Ruby, the Spinel-lowered class files under
CRuby, and actual native Spinel with emitted signatures. Stateful phase/count
controls check both call ordering and once-only evaluation. Other targets that
do not carry ordered class-body execution refuse these capture initializers.
This is **not runtime method-installation/presence staging**, model-owned runtime
definer support or the original stateful SiteSettingExtension. The ordinary
module's immutable/no-observer admission guards remain unchanged. No additional
pure-source subset was added for this prerequisite.

## Bounded complete settings dependencies (diagnostic only)

The strict target's separate settings experiment now supplies **17 complete
original Ruby files plus2 original resources (332,105 bytes)**, not only the
SiteSetting/extension pair. This includes GlobalSetting/GlobalPath, original
mixin/default/type/YAML/provider/dependency/label code, Enum and actual complete
plugin sources. Every copied byte/hash is audited before and after. The source
lock has36 complete pinned files; none of these inputs is a settings snapshot.

Original `config/application.rb` and `005-site_settings.rb` are **boot inventory
only**, not compiled as a misleading partial bootstrap. They expose real
configure/provider registration/load_defaults and refresh/cache effects that
remain unproved. The helper refuses to find either boot file in its diagnostic
compile tree. No actual private discourse.conf is copied. Output with unsupported
diagnostics is **never executed**, and this experiment cannot pass019.

The expanded input first failed at original registry `@@register_names = Set.new`.
The reusable ingest/emission fix preserves runtime native class-variable
initializers in source order alongside constants and ordinary class-side calls;
it does not replace the constructor with a literal. Native/CRuby regressions
check once-only order, inherited aliases/reassignment, and lexical module
ownership. Spinel's blanket unverified `@@` read/write diagnostic was removed
only after actual native execution; runtime `defined?`, unpositioned includes
and mixed mattr/cattr defaults retain their separate unsupported boundaries.
The expanded diagnostic now advances past that failure and still explicitly
refuses real registry declaration guards and original setting getter names.

The next bounded prerequisite handles original-style root declaration guards:
`return if respond_to?(register_name)` sees source methods already installed,
including earlier successful expansions, not Spinel's final table. Only a single
root, data-only bootstrap/argument context without callbacks/overrides is admitted;
opaque effects, core/framework uncertainty, inherited/namespace contexts and
unshared literal composite captures remain refused. Direct primitive class-state
events retain the call/ordinal order. Literal class-self ivar reflection in a
proven generated reader becomes typed Ivar/Assign IR without bypassing overrides
or crossing nested blocks. Native controls prove duplicate/false registration,
constructor capture, cache identity and instance shortcuts.

The **actual complete original registry diagnostic** now emits `javascripts` and
other unfiltered register methods with their state events and original source
markers. Guarded same-run old/alias/new snapshots now preserve both definitions
and replay actual native `alias_method`, not a clone/forwarder. Owning controls
cover raw cache mutation, filtered access, instance shortcuts and method/callee
identity under original/lowered CRuby and native Spinel. Alias chains, multiple
aliases of one version, preexisting sources, missing replacements and lifecycle
observers remain refused. A subsequent guarded block-frame implementation now
answers `block_given?` from the actual helper frame and restores the caller frame
after nested registration. Literal `yield(self)` callbacks may execute direct
method definitions; their yielded parameter captures the fixed root class, not
the generated method's inherited runtime receiver. Original/lowered/native checks
prove the callback runs once and is skipped on duplicate registration, without
suppressing hooks or arbitrary callback effects (which remain refused).

The actual complete original diagnostic now emits the original
`reviewable_types_lookup` callback and filtered class-body declarations. It is
still NEVER executed: real `Plugin::Instance` runtime calls at original1037 keep
the original dynamic registry factory helpers alive/refused, and original
SSE1143 still lacks runtime-name declaration support. Stateful model/YAML
installation, actual plugin boot and real settings service execution remain
unproved. Native inherited cache isolation exposed a separate Spinel defect:
literal reflective self-calls were missing class-ivar specialization; the focused
`ecc1813f0` fix and10native inheritance/alias/override controls preserve actual
receiving-class state. No app getter or callback was replaced.

A further lifecycle owning repro preserves real source `self.extended(receiver)`,
receiver/module identities and the following class/module-body observation. It
exposed an independent typing barrier: each class-object initializer was analyzed
with an empty ivar environment. Initializers now use a separate nil-widened join
of initializer/class-method writes, excluding instance fields and retaining
callback nil/type changes. Empty and seeded traces pass original/lowered CRuby;
root/module lifecycle and nil-changing controls pass native Spinel. Existing
runtime hook replay is preserved, not implemented as a stub or silently omitted.
The complete original diagnostic still retains original SiteSetting `extend`,
original SSE `extended` body and the SSE1143 refusal. Actual model bootstrap,
GlobalSetting configure/resource-derived names and production settings execution
remain unproved. A synthetic AR-model host additionally proves extension method
installation before the original-style `extended(klass)` callback dispatches to
that protected method via `send`, then the model body observes the effect once.
An actual ActiveRecord-gem original reference and identical lowered CRuby/native
consumers pass without DB/cache operations. No model lifecycle implementation was
invented: existing hook replay already worked once initializer reads typed. This
is not actual SiteSetting bootstrap or runtime setting-name installation.

A further captured-self control exposed a real identity defect: replacing
`captured = self` with a method-body SelfRef rebound the captured declaring class
on inherited calls. Guarded explicit and yielded-class captures now share one
ordered self slot; getter self stays dynamic. Constant-added observers are refused
rather than acquiring extra synthetic callbacks. Original/lowered CRuby and
native controls pass. Its separate direct class-method `return self` RBS/ABI
failure is also fixed through the existing all-class-object return harvest:
class-method self is a class object, not an instance pointer. The stronger direct
return and inherited identity test is restored, with an instance-self negative
control; original failed C/signature evidence remains preserved. Mixed non-class
return shapes keep their prior conservative boundary.

The next runtime-name boundary is independently measured: even a literal call
outside the staged declaration path, or an ARGV-derived name, is refused natively
as an undefined installed method. A generic explicit-receiver captured closure
can read separate root/subclass storage correctly, but this ABI feasibility is
NOT runtime definition-event/presence/alias support and no original getter was
replaced with it. See the current handoff for the precise failed/positive inputs.
A generic stored-Proc alternative was investigated but rejected as an implementation
strategy for now: current Spinel `instance_exec`/`instance_eval` cannot rebind a
stored capturing Proc's self, unlike inherited define_singleton_method bodies.
No replacement getter or plain Proc.call shortcut was installed.

Input provenance now records the actual Spinel executable SHA256 and full version,
and rejects a build-revision label that differs from the recorded source HEAD.
The task compiler's earlier precommit version header was refreshed from unchanged
source; that was only a build/stamp correction. A later independently reproduced
compiler defect is now fixed in Spinel `d4415155b`: an earlier definition captured
under a public alias name used the original name for `__callee__` when no call-site
channel was present. The fallback now uses the named captured scope, excluding
hidden/version/proc scopes; `__method__` still retains the original definition name.
Six focused native alias/capture/super controls pass. Earlier failures remain
preserved; fresh exact-head runs carry the actual executable identity.

## Historical safety disclosure

The Nov2 blocked handoff and failed evidence remain preserved. Two early Rails
boots used PG read-only but lacked a Valkey guard and could perform startup cache
writes; they are not the accepted all-path isolated proof. Nov3 runs use the
owned fixture and fail-closed guards; no shared cache rollback/reset or service
restart was attempted.

Discourse sources: Copyright2014–2026CivilizedDiscourseConstructionKit,Inc.and
contributors, GPL-2.0-or-later. Original licence included. Runtime/driver components
retain their own notices. No pushes/PRs/Hub/live-app deployment authority is implied.

## Nov4 actual module-extension/source-storage checkpoint (not019 acceptance)

Roundhouse now records the actual SiteSetting extend event and types SSE instance
producers against their owning Class, without copying methods or replacing its
real callback. Source class-load ivar effects and module API calls retain their
order. Reduced original/lowered/native controls cover early refusal, callbacks,
separate module/owner storage and inherited receiver storage. Actual argument
producers improve load_settings/hook signatures; actual registration writes close
`themeable` to Hash[Symbol,bool]. Unknown writer and ownership controls refuse.

The source-locked whole additional dependencies preserve their original bytes,
not selected stub methods. On this checkpoint the original SSE1143 getter still
reports51 unresolved body nodes plus optional callable ABI and return frames;
full Discourse also retains its original conditional-definition212 refusal.
Acquisition/type progress is NOT runtime boot, registered YAML settings, plugin
startup, original getter/security/direct-PG or019 acceptance. Current/theme/plugin
values and YAML-yield closure remain unproved. All previous failed proof history
is retained under build; strict019 remains nonzero and unchanged in its contract.
