# Original core /latest — separately labelled no-plugin milestone

Sam's Nov5 scope change makes **no plugins loaded**, including official plugins,
the first milestone. Full/plugin-enabled019 and all historical failures remain
separate and UNACCEPTED. No gate, ceiling, diagnostics or original checkout is
changed by this experiment.

Pinned original configuration: `app/models/global_setting.rb:388-413` interprets
`LOAD_PLUGINS=0` as `:none`; original `config/application.rb` guards provider
registration and `Discourse.activate_plugins!` using `GlobalSetting.load_plugins?`.
This is not setting every plugin's enabled flag to false.

Run `python3 tools/probe_core_no_plugins.py`. It boots the guarded, original Rails
reference FIRST using LOAD_PLUGINS=0. A test-only script-compilation TracePoint
fails before executing any Ruby file beneath the original plugins/ directory;
post-boot loaded features and `Discourse.plugins` must both be empty. Both switch
source files are pinned/hash-checked. PG stays read-only5499, Valkey effects use
only the separately owned guarded disposable fixture; cleanup/source/effect
checks from the existing oracle remain intact.

Evidence **build/probe-core-no-plugins-20261105-081600**:

- Actual original `TopicQuery#list_latest` (source305) and `TopicList` produce
  20 nonempty live topics, with actual original query SQL preserved as reference
  observations ONLY, never native inputs. No plugin source compiled/loaded and
  no plugin instance loaded. All original settings remain dynamic.
- Original initializer/options methods vs native ELF and SAME lowered CRuby
  match page0/page1 copy/identity semantics and the COMPLETE invalid-option
  message. No plugin key names were seeded or trimmed. This is only a constructor
  prefix, NOT native full-query, boot, serializer, controller, document or page.
- Native complete original TopicQuery/TopicList candidate still strictNONZERO:
  69errors in missing core dependencies. Compiler order is not runtime order.
- Original query call trace identifies the FIRST actually reached setting:
  `SiteSetting.nested_replies_enabled` via original
  `SiteSettingExtension#setup_methods` generated reader at1143. Later actual
  core reads include tagging/localization/muted-category/muted-tag/shared-draft
  settings. Reader cold provider/default/refresh/cache effects are core work;
  no plugin activation/SeedFu campaign is required absent measured core need.

Earlier081407 retained a runner matrix bug (page1 native ran the whole matrix).
081508 retained a repeated-oracle harness problem: a second invocation inherited
phase=oracle into isolation UNIT negative tests and appended their expected
rejections to the original run log. Endpoint guards were not weakened. The
corrected runner compares with the independent FIRST reference only; its data
is never used by native runtime. Clean081600 preserves the full safety/effect
and cleanup proof. These earlier errors are not implementation acceptance.

Current compiler WIP is preserved by coordinator preemption commits
Roundhouse012ae4087/Fidelityc97344d; SeedFu/literal-feature work is DEFERRED.
Next: actual original core controller/JSON/document reference and source-labelled
reachable core input; solve the true core getter/provider closure rather than
porting unrelated primitives or assuming production values/defaults.

## Actual core controller/serializer reference and source acquisition

**build/probe-core-no-plugins-20261105-082548** invokes original Rack without a
server, using the original base URL and explicit HTTP_HOST (host protection is
not disabled). `/latest.json` returns200 with actual original controller and
serializers,20topics and the core users/group/topic-list document fields. A
script-compilation observer still proves no plugin files/instances. `/latest`
returns503: original EmberAssets reports no generated frontend manifest. This
is an environment/frontend build obligation, NOT successful document/page proof.
The first082114 request lacked HTTP_HOST and correctly returned403; that raw
failure is retained, not hidden by changing host protections.

`core_source_inventory.py` pins141 complete original core files observed in
query/controller/serializer calls, including existing sources;115 were newly
acquired. This is NOT a closed-world projection or proof that unobserved branches
are unreachable. Every complete source is checked against96ce8d444 and the clean
original checkout. No response, SQL text or setting value is used as native input.

**probe-core-no-plugins-20261105-082828** adds a separate compile-only FIRST core
setting candidate. Complete original SiteSetting/extension/YAML/provider/type
code and the REAL005-site_settings initializer are retained. Catalog schema is
SELECT-only and contains no production setting values. Plugin activation files
are excluded; the core passive DiscoursePluginRegistry API remains original.
The candidate strictFAILS170errors: the reached original reader at1143 has52
unresolved callable nodes, optional-argument/method-frame obligations and model
receiver/storage proof still needed. Unexecuted registry SeedFu APIs are not a
reason to resume a plugin/SeedFu campaign. Failed/error output is never executed.

## Source-driven callable frame prerequisite (NOT the getter)

Roundhouse786b50d5e adds a bounded nil-optional positional/early-return profile
for otherwise closed typed singleton families invoked with ZERO source arguments.
Real optional formals are retained (not local-assignment emulation), preventing
capture/mutation of a same-named live factory local. Source Method arity(-1),
receiver, __method__/__callee__, aliases, snapshots, reinstallation and every
callback remain. Explicit arguments, other defaults/formals, reserved-name
collisions and unresolved worlds keep their original refusal. Original/SAME
loweredCRuby/native proof **probe-core-callable-frame-20261105-084834** retains
Ruby/RBS/ELF hashes and direct native no-service process trace. This reduced
control does NOT execute the core getter, provider, refresh or /latest.

Family profile6PASS, native old/new controlsPASS, fullytyped runtime invariantPASS.
Known global936>920 remainsFAIL and unchanged. Original core reapplication with
the fix at **probe-core-no-plugins-20261105-083938** is still strict-nonzero for
fullquery/getter and retains core constructor parity; no unsupported diagnostics
were weakened, no full/plugin gate changed. More model/receiver/type/provider
work is necessary before any native core query/JSON/page acceptance request.

## Model class-owner prerequisite (not native core execution)

Roundhouse `3fa047808` extends the guarded shared runtime-family lowering to
single-declaration, direct-ActiveRecord source model class objects without
replacing or duplicating the model. The original empty class hash seed now
uses the existing container-aware ivar-slot join with concrete class-method
writes. Exact reduced proof: `build/probe-core-model-owner-20261105-092847`;
original installed ActiveRecord, same lowered CRuby and direct native ELF match,
with source/output/ELF hashes and no child process or service connection. Full
runtime-family suite14PASS (including native/full-framework controls), runtime
fully-typed invariantPASS, conservative model-world negativesPASS.

Immediate reapplication to the unchanged original core getter candidate remains
strictNONZERO: `build/recovery14-model-owner-core-getter.stderr`,19unsupported
and151type errors, reached original1143 reader still52unresolved nodes. The
larger actual extension/includes/metadata/provider/refresh closure is NOT
admitted by this reduced capability. No failed output was executed and no core
query/serialization/document/browser acceptance is claimed. Historical
full-plugin019 and the global gradual936>920 failure remain unchanged.

## Nested core storage and measured provider dependencies

Roundhouse `a471aee4d` derives the original per-site memoized container shape
from actual indexed writes, without freezing a site key or setting value. Its
empty indexed `||=` seed retains the receiver's nested element contract.
Original/SAME lowered CRuby/native reduced extension proof changes sites at
runtime, verifies cached values remain separate, and counts each site-key
lookup exactly once: `build/probe-core-nested-reader-20261105-094832` PASS.
Extension suite10PASS, class-storage12PASS/2existingignored; runtime9PASS with
only the unchanged concretely-typed gradual failure936>920.

Exact committed release SHA
`5d46ab11dec467c892d2e3de98296eef720d1763094560409774b9f86615744f`:
`build/probe-core-no-plugins-20261105-095240` rechecks genuine no-plugin Rails,
query, real controller JSON200, HTML503, complete constructor/error parity,
endpoint negatives, owned fixture cleanup and unchanged original bytes. Full
query still69errors; first getter candidate still170errors and unexecuted;
the reached original1143 reader now50unresolved nodes, NOT closed or admitted.

`--getter-input --provider-dependencies` is a separately labelled compile-only
expansion around the actual unresolved provider/site key. It retains original
`000-mini_sql.rb`, `MiniSqlMultisiteConnection`, and verified locked MiniSql1.6.0
and rails_multisite9.0.0 source packages (all original Ruby library members and
licenses), using existing source-gem feature context. Metadata is explicitly a
reduced compiler context, not a replacement/full original Rails boot. Original
`005-site_settings.rb` remains; no initializer/Railtie body, database facade,
SQL, coder or callback is synthesized. Both original gem versions/package hashes,
installed/package/source equality and original runtime lock are checked.

First measurement `build/probe-core-no-plugins-20261105-095443` remains strict
NONZERO:91unsupported+186type errors. This is a larger candidate, NOT a regression
against the smaller170error input or native success. Original multisite source
now types the actually used `provider.current_site` expression as String;
setting elements remain unresolved. Actual next dependencies include genuine
MiniSql raw PG/coder APIs and anonymous row materialization (`Class.new`, dynamic
accessors and original String instance_eval), plus keyed YAML options/core
refresh effects. Unexecuted MySQL/SQLite/JDBC candidate failures are retained,
NOT a reason to port their drivers. Plugin activation and plugin-only String
eval work remain deferred. No failed candidate output was compiled or executed.

Cold provider observation **build/probe-core-no-plugins-20261105-100409** records
11,631 ordered original call/return/row-factory events,22 actual loaded package
source hashes matching the verified archives, and genuine anonymous row fields
`name,data_type,value`. The real PG type-map path executes; original evaluated
row code observes44String and22Integer `getvalue` results. These are observations
ONLY, not native types/values/SQL inputs. No application method is wrapped or
replaced; required boot/cache effects and endpoint negatives/fixture cleanup hold.
The first100133 instrumentation error (Ruby4 C-call events have no Binding) is
retained; it exited with owned fixture cleanup. The corrected observer reads the
original Ruby attr_accessor line frame and follows actual compiled-eval paths.
Type/field/order/source-hash tampering controls fail closed (profile suite8PASS).

A concrete source-context defect is now isolated: source-gem mount discovery
follows BOTH arms of original `RUBY_ENGINE == 'jruby'` autoload registration.
It consequently ingests the mutually exclusive PostgreSQL and JDBC definitions
of `MiniSql::Postgres::Connection` as a reopened parent. Source constructor
lookup correctly refuses this ambiguous input. The actual no-plugin CRuby run
loads the original PostgreSQL source, not JDBC. Compiler diagnosis snapshots:
`build/recovery14-core-provider-pg-owner.json` contains both definitions;
`build/recovery14-core-provider-arpg-owner.json` retains the genuine inherited
initializer. Next fix must preserve original engine/feature ownership and load
effects or remain refused, NOT arbitrarily merge owners, pick the first class,
remove errors, or port the unreachable JDBC/MySQL/SQLite drivers.

## Actual engine-owner correction, still not native core acceptance

Roundhouse `f4a883603` adds explicit target-aware source-gem ownership. Only
predicates agreeing on original CRuby and Spinel select dependencies; source
consumer APIs retain both alternatives. The Spinel inventory must use the finite
feature graph, not an eager declaration aggregator or Ruby target's reflective
fallback. Ordered real file effects, constructor/keyword ABI and source feature
identities survive. Engine/core overrides, explicit alternate imports, opaque or
computed app-root effects, incompatible targets and late IR mutations refuse.
Exact committed reduced proof: `build/probe-core-engine-context-20261105-111555`,
original/SAME lowered CRuby/native + byte hashes/direct no-child/no-service trace.

Current native original core candidate removes the fictitious PG/JDBC parent
reopen/constructor ambiguity and remains strictFAIL90unsupported+185type
(275total), including an actual finite-loader refusal:
`RailsMultisite::ConnectionManagement` has multiple feature declaration contexts.
Original first1143 reader still50unknown nodes. Evidence before committed release
reapplication: `build/recovery14-core-engine-current.stderr`. No failed output was
executed; source namespaces must preserve their genuine initial creation/opening
and nested class lexical context, not merge or pick a parent implementation.

Verified: source engine5PASS including native/effects/negative controls; old
source resolver7PASS; constructors14+10PASS; runtime family14PASS and extension
10PASS including native/full-framework controls. The aggregate command timed out
at its final engine control after family14/extension10 completed; a fresh engine
suite completed5PASS. Native feature suite14PASS plus one deferred frozen-literal
WIP FAIL. That previously preempted test is now measured: frozen original String
is thawed by generated constant-feature Ruby. It also reproduces with the PREVIOUS
committed release SHA5d46ab11dec467c892d2e3de98296eef720d1763094560409774b9f86615744f
(original=true, lowered=false), archived as
`build/recovery14-frozen-committed-baseline.*`. It is retained, not dismissed or
fixed as unrelated work. Runtime suite9PASS/known936>920FAIL remains unchanged.

## Namespace-feature prerequisite, not provider/page acceptance (Nov5 12:27)

Roundhouse `0bbe26eec` retains source-only class namespace openings and each
helper's own feature, instead of merging its declarations into the parent's main
body. Original / same lowered CRuby / native controls preserve early method
absence, constant NameError and later lexical lookup, real child inclusion and
construction, repeat-load cache and effect order. Source/member/binding/callback
and namespace-constructor/value-lifetime negatives remain refusals. Spinel
`27d47fe8d` separately fixes qualified Class.respond_to? using source-point method
history. An early-constructor mismatch was measured and is NOT claimed fixed;
that namespace construction/value world is excluded from this bounded profile.

The unchanged expanded original core candidate STILL has strict nonzero
90 unsupported +185 type diagnostics, including a precise refusal of the genuine
singleton-delegated `RailsMultisite::ConnectionManagement.current_db` API. Do not
make that API available by weakening the namespace guard: lower and verify the
original singleton macro/callable closure. Original getter/query/serializer/page
native execution remains UNPROVED. Known frozen-literal and global typing
failures are retained. No new service or PG activity was needed for these
compiler controls or the compile-only reapplication.

## Recovery15: original multisite boundary and literal allocation (Nov5 14:35)

The release-O3 rustc process crashed with SIGSEGV, not a failed application test.
No identical blind rebuild or source/gate weakening followed. With the already
working test-O1 level as evidence, a bounded CPUs0–3 O1/LTO=false release-profile
build of clean Roundhouse `e62da954c` succeeded (183s, ~5GiB peak RSS). Exact
settings/toolchain/source/binary are in `recovery15-bounded-opt1.json`; the O3
crash remains unresolved. That compiler immediately reapplied original inputs:
unchanged strict91unsupported+196types, expanded genuine patch92+204, never run.

Complete pinned `002-freedom_patches.rb` and `lib/freedom_patches/rails_multisite.rb`
are now acquired, not a fake safe_each_connection method. The remaining glob
closure and candidate bootstrap are explicitly UNADMITTED. Guarded original
**probe-core-no-plugins-20261105-134422** confirms the helpers first create the
namespace with no current_db/DEFAULT, then the gem defines its API, then002 loads
the real patch on the SAME class object before005. Original callback execution
counts and every selected return-type count are recorded; unique source points
are explicitly diagnostic coverage, NOT the earlier full cold provider trace.
No observed class/value is supplied as native input. Query reference20rows,
no plugin instances/sources. Endpoint negatives, readonlyPG, real owned cache
and original read-only Vips child effects and cleanup all remain checked. First
134254 failed on omitted Vips attestation; its failure and cleanup remain, then
the runner used the existing original-source attestation, not a suppressed hook.

Separate full-Rails POSTBOOT patch renderer carriers initially failed exact
comparison: source-frozen lookup String became mutable. That actual core failure
justifies repairing source literal allocation, rather than finishing unrelated
plugin-only frozen-literal work. Roundhouse `2edc687b6` carries source policy in
shared declaration/resource plans and emits the original directive; it does not
call String#freeze, freeze runtime values or insert oracle data. Mixed policies
in one physical file still refuse. New original/shared-Ruby/native allocation
controls3PASS, finite feature15PASS (the retained frozen-version failure now
fixed), namespace4PASS, engine5PASS, actual-original patch IR1PASS. Real-blog6PASS;
runtime9PASS and known936>920FAIL retained. Delegate28 and forwarding31PASS.

**141810/141813** separate postboot full-Rails carriers now compare the COMPLETE
original patch's callback results/types, nonlocal return, branch behavior,
callable descriptors and actual source frozen state. This is NOT candidate
load-order equivalence, cold-cache parity, standalone compatibility or native
execution. The original Source::Yield/rescue/DEFAULT/deferred dependency clauses
and full-forwarding formals remain in IR; native forwarding and multi-body
namespace lifetime still REFUSE. Original native getter/query/page unaccepted.

Next concrete architecture boundary: a method/field/Singleton producer needs a
SOURCE construction/lifetime witness, not the observed NullInstance type nor
Ty::Class (which conflates instances and class objects). Source main/patch
member features also need separate execution identities on one class binding;
002's immediate require and deferred glob must remain real ordered effects.
No first-record merge, zero-arity delegate, source patch substitution, or dropped
callbacks can make this milestone green.

## Recovery15: source producer and native packet design (Nov5 15:20)

Roundhouse's source-labelled refusal now names the actual unpositioned
`lib/freedom_patches/rails_multisite.rb` declaration instead of hiding it behind
the generic multiple-class message. No body is merged, no callback moved and no
native guard removed. The actual source keeps both configured and NullInstance
producer/receiver arms, regardless of the oracle's observed null-instance choice.
The earlier broad factory-type-conflation hypothesis was falsified: simple
factory signatures distinguish SelfInstance, an instance Class, and Class[T].
The existing source construction/writer/lookup proof is still required.

The exact expanded original input remains strict RC1, 92 unsupported + 204 type
errors, on committed RH bdac05e75. Previous getter91+196 and query69 errors remain.
`recovery15-source-producer-*.json` retains all source hashes/build provenance;
failed candidate outputs were never executed. Producer2, actual original audit1,
namespace5 and source-engine5 pass (native namespace/engine prerequisites only).

The complete existing shared-IR singleton control was also compiled directly,
with BOTH genuine ActiveSupport delegation runtime source files resolved through
the installed gem, without deleting methods, descriptors, callbacks or drivers.
`probe-core-full-delegate-native-diagnostic-20261105-150533` refuses with two
specific diagnostics: ForwardingArgumentsNode in same-named builtin delegation,
and dynamic Method lookup in the descriptor check. No binary was produced.
This is a measured native gap, not a source-only parity claim about native code.
`tools/probe_core_singleton_delegate.py --native-diagnostic` can reproduce that
full diagnostic while preserving the mandatory Roundhouse native guard.

A bounded forwarding design experiment preserved the syntax channels by changing
all-still-full target shapes to anonymous `*, **, &`. It compiled the isolated
same-named builtin case but ran INCORRECTLY (NoMethodError for nil.to_s instead of
its real result/argument errors). Thus rewriting the packet alone is NOT a sound
fix: the typed builtin path lacks a checked rest/keyword packet entry. The trial
patch, generated C, baseline refusal, original stdout and incorrect native output
are retained under `build/recovery15-forwarded-builtin/`; the unsafe source trial
was NOT adopted. Only that new experimental edit was restored, and the restored
Spinel binary hash exactly matches the initial binary. No prior WIP was removed.

Next constructive packet design needs a checked builtin count/channel entry
(including empty vs nonempty keywords, once-only evaluation, exact errors and
block lifetime), not an arity inferred from callers or a dropped keyword Hash.
Actual main/patch member-feature identities and initializer002's immediate plus
deferred execution still need separate proof. No core provider/getter/query/page,
plugin or full019 acceptance follows from these controls.

### Complete callback/error controls and actual initializer phases (15:40)

The genuine original/shared-IR POSTBOOT patch comparison now also executes:
no-block calls, caller `break`, `catch`/`throw`, and callbacks raising each actual
PG::ConnectionBad / UnableToSend / ServerError class. Strict preconditions require
only the genuine default site before any fault is raised, preventing entry into
a nondefault failover branch. No PG error is injected into a real connection;
these are callback exceptions, not new DB effects. A genuine ArgumentError callback
executes the original StandardError rescue and its real STDERR.puts, observed by
TracePoint without replacing the logger. Complete actual urgent error lines match;
full raw backtraces retain original/generated source paths in separate process
logs. Both original and shared-IR carriers still perform the original no-plugin
query first. Archives153844/153847 PASS thirteen result records/descriptors/error
lines and owned-fixture cleanup. NOT candidate bootstrap, cold-cache or native.

The original002 observer now records EVERY selected require-attempt iteration
rather than only unique source points. Actual archive153839 records one immediate
multisite require and22 deferred other freedom-patch requires; the full23-file
census is independently checked against pinned Git bytes. These are ATTEMPTS,
not inferred require-return success or native source inputs. The measured order
is immediate patch ->005 registration ->002 deferred requires ->005 deferred
settings callback. A first overbroad assertion that ALL005 source points precede
the deferred requires was falsified (archive153730 retained, cleanup passed) and
corrected to distinguish registration from deferred callback body execution.
Checker negatives detect missing/duplicated targets, changed census, wrong phase,
namespace identity, callable arity and returned class objects. The other22 files
are not silently treated as compiled/admitted native closure.

A second bounded native design trial added class-side runtime-name Method lookup.
It compiled but FAILED parity: Method#parameters leaked synthetic __anon_* slots
instead of the genuine :*, :**, :& parameters, despite matching arity. The trial
patch and full outputs are retained under
`build/recovery15-dynamic-class-method-descriptor/`; that partial change was NOT
adopted. Spinel source/binary were restored exactly, preserving all pre-existing
work. A source lookup or return-arity proof alone cannot grant the full carrier
or reflective descriptor contract. No compiler guards were weakened.

### Member-feature design boundary and scoped Class-local prerequisite (16:18)

`build/recovery15-member-feature-identity/` separates four source compiler
controls: Class-local vs qualified receiver, and conditional vs unconditional
require placement. Conditional loads remain UNPROVED; the narrower qualified,
unconditional control matches original/native class identity, callbacks, future
API absence, values and repeat-require effects. A Class-local unconditional
variant exposed future methods. A source-witness fix in Spinel now gives that
local the existing constant receiver's load-point method history ONLY when one
plain direct program assignment precedes the read in the same file, has no other
scope writes and resolves to an already-bound class in source elaboration.
No inferred Class return type, factory or observed runtime value is a witness.

Spinel load-graph suite passes, including new member-feature callback/private
visibility/builtin/source-local controls and separate captured/conditional writer
and real response-protocol exclusions. Full forwarding and Roundhouse member
feature/value/constructor guards remain. A combined unrelated own-protocol world
and a respond_to_missing? case still expose native debt; no broader reflection
support is claimed (missing-hook baseline mismatch retained). Failed conditional
variants and the earlier failed source witness are preserved, not relabelled.
The concrete next IR change is declaration-fragment identity separate from the
one runtime class binding, NOT a first-record or early-body merge.

Renderer validation now also requires every callback/control row, both branches,
all four error cases, nonlocal/break/throw results, exact descriptors and actual
error lines, independently of equality between the two runs. Checker corruption
negatives prevent a matching omission in both carriers from becoming a pass.
