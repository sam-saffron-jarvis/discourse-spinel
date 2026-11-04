# Compiler changes

Read [AGENTS.md](../../AGENTS.md) for invariants. This page helps locate the
owner of a change; [pipeline internals](../pipeline/) and [compiler inputs](../data/)
explain the individual stages.

## Ownership map

Application emission follows Ruby/template ingest → analysis → shared
post-analyze lowering → target emission → packaged project/runtime.
Source consumers (check/LSP/MCP and `emit_preview`) intentionally analyze
without that shared lowering sequence; see [`src/session.rs`](../../src/session.rs).

| Responsibility | Start here |
|---|---|
| Expression IR / application structures | `src/expr.rs`, `src/dialect.rs` |
| Prism → IR | `src/ingest/expr.rs`; other inputs under `src/ingest/` |
| ERB/HAML → Ruby | `src/erb.rs`, `src/haml.rs`, `src/ingest/view.rs` |
| Type / effect inference | `src/analyze/body/mod.rs`, `src/analyze/effects.rs` |
| Method catalog / DB adapter | `src/catalog/`, `src/adapter.rs` |
| Shared lowering / pass order | `src/lower/mod.rs::POST_ANALYZE_PASS_ORDER` |
| Target syntax | `src/emit/` |
| Target identity (`BuildTarget`) | `src/build_target.rs` (wasm-safe; `project` re-exports it) |
| Project assembly / target dispatch | `src/project.rs::target_files` |
| Gem requires / Gemfile declarations; project extensions | `src/gems.rs`, `src/extensions.rs` |
| Framework sources / shared transpile driver | `runtime/ruby/`, `src/runtime_loader.rs` |
| Hand-written target glue | `runtime/<target>/` |

Framework behavior belongs once in `runtime/ruby/` or a shared lowering, not
as the same special case in several emitters. The runtime loader shares its
transpile driver through target hooks. New Ruby runtime files also need
registration in `src/project.rs::spinel_files`.

Every Ruby file under `runtime/ruby/` and `runtime/spinel/` uses
`# frozen_string_literal: true`. The directive follows an optional shebang
and precedes generated requires. `tests/runtime_frozen_string_literal.rs`
checks all runtime Ruby files.

Other entry points: `src/bin/` (CLI/debug tools), `wasm/` (browser compiler),
`editors/vscode/` (LSP client), `tools/compare/` (standalone differential oracle).
`scripts/` drives workflows; `tests/`, `e2e/`, and `tests/browser_smoke/` carry
the regression and browser harnesses.

## Adding an IR variant

1. Declare the variant in `src/expr.rs`. Retain source distinctions needed
   for expression IR round-trip; do not impose whole-app source preservation.
2. Ingest the construct in `src/ingest/expr.rs`. Unsupported shapes must
   produce an honest diagnostic, not disappear.
3. Update both type inference and effect traversal. An exhaustive match
   catches missing variants, not missing recursion or wrong effect propagation.
4. Add a shared lowering when targets need a simpler/common shape. Respect
   declared pass ordering and inspect all downstream walkers of the new nodes.
5. Implement correct target emission or keep the unsupported boundary explicit.
   Ruby expression emission must support snippet IR stability. Other targets
   are not permitted to silently approximate a construct accepted by `check`.
6. Pin ingest, inferred/lowered shape, and semantics with the appropriate
   [tests](testing.md#choosing-tests). Removing an error requires an emitted
   regression in `tests/emit_and_run.rs`, not just fewer diagnostics.

```sh
cargo test --test ingest
cargo run --bin roundhouse-ast -- --round-trip -e '[:a, :b]'
```

## Semantic checks

Preserve evaluation order, short-circuiting, and once-only evaluation. Use
asymmetric values and an effectful operand in regression tests where duplication
or reordering could be hidden. A pass that cannot preserve semantics must leave
an explicit unsupported/residue boundary rather than emit plausible wrong code.

Class-macro expansion records runtime events with `ExprCold::declaration_step`
(call span plus ordinal), on generated constant initializers and method-body
roots. This is execution order, not a replacement for original expression/name
spans. Ruby-family class bodies interleave those events at the declaring call;
targets without class-body execution refuse the captured initializers. Literal
String values inside the evaluator retain allocation handles: equal text is not
alias evidence, and folded allocating operations keep mutable String intent.
This does not stage native method-table presence or broaden the guarded
ordinary-module/stateful-model declaration boundary. Owning checks live in
`tests/declaration_capture_runtime.rs`.

Direct native `@@` initializers also use source class-body order rather than
requiring a literal value: constructors must run once at their actual statement.
`LibraryClass::is_source_class_initializer` keeps those writes distinct from
synthetic mattr/cattr seeds. Unpositioned includes/mattr defaults retain explicit
refusals. Spinel native lexical/shared class-variable storage is exercised by
`tests/runtime_class_variable_initializers.rs`; runtime `defined?` admission is
not inferred from read/write support.

Guarded root-owned declaration factories can answer `respond_to?` from their
actual source-order method surface and prior expansion results. They do not use
the native final table. The admitted body has one root opening, data-only
bootstrap/arguments, no lifecycle/reflection override, and only known declaration
calls; core/framework uncertainty stays unknown. Direct primitive class-state
events retain declaration ordinals. Literal class-self ivar get/set in generated
class readers canonicalize to Ivar/Assign IR only without overrides, never across
nested blocks. Composite literal captures/state aliases and opaque bootstrap
helpers remain refused. See `tests/guarded_declaration_state.rs`; stateful
module/model installation and general runtime method presence are not implied.

Within that guarded run, a class method may be defined, aliased once, and then
replaced under its original name. `ExprCold::method_alias_source` distinguishes
the semantic snapshot from a forwarding body; the copied body supplies typing,
while Ruby-family emission replays native `alias_method` in call/ordinal order.
Both old and new definitions survive. Only this proved same-run duplicate bypasses
the normal redefinition refusal. Preexisting sources, alias chains/multiple aliases
of one version, missing replacement, callbacks/reflection overrides and targets
without ordered alias replay stay refused. `tests/staged_singleton_aliases.rs`
checks cached-object identity, instance shortcuts and `__method__`/`__callee__`
under original CRuby, identical lowered CRuby and native Spinel.

Guarded root factories also retain current-method-frame block presence across
nested helpers. A literal class-body callback with one plain parameter may be
invoked by `yield(self)` only when its declaration-time statements are direct
literal-named method definitions. The yielded parameter captures the fixed root
class object in the same ordered self-capture slot as an explicit declaration
`captured = self`, while the generated method's own `self` still follows inherited
receivers. Original callbacks are evaluated, not omitted; no generic Proc-store
or self-rebinding shortcut is used. Source block locals/destructuring/optional or
rest parameters, splatted/multiple yield args, non-declaration effects/control
flow, callback/reflection overrides and module/model lifecycle contexts remain
refused. See `tests/literal_declaration_callbacks.rs`. Actual original registry
class-body callbacks now expand, but real Plugin::Instance runtime factory edges
keep their unsupported original helper bodies; settings runtime names remain
outside this bounded declaration route.

Class/module-body initializer reads use a separate conservative class-object
storage environment: first type RHSs, then join writes from original initializers
and class-receiver methods, widen with nil, and retype the initializers. Instance
method fields cannot leak into that environment. In particular, an extension
callback's nil/type-changing class write must not be folded using an earlier
non-nil initializer seed. `tests/extension_lifecycle_runtime.rs` proves real
source `self.extended(receiver)` dispatch/identity and following-body observation
on a root class and module under original/lowered CRuby and native Spinel, plus
fixed storage-join types and a nil-changing callback. This preserves the existing
runtime hook; it does not partially evaluate or omit it, nor relax stateful model
or module declaration guards. A separate model host now proves that an extension's
protected instance method is installed before its real `extended(klass)` callback
calls it via `send`, and that the following model-body statement observes the
callback exactly once. The reference uses the actual ActiveRecord gem; identical
lowered CRuby/native controls use no database operations. This is a synthetic
owning bootstrap fixture, NOT actual SiteSetting/provider boot or runtime YAML
method-name support.

`tests/declaration_self_capture.rs` distinguishes a guarded declaration's
captured class object from a generated method's dynamic self on inheritance.
Both explicit captures and yielded-class captures share an ordered self slot;
no body substitution rebinds the capture or re-reads a class name. Constant-added
observers remain refused so synthetic slots cannot add observable callbacks.
The same control exposed a class-method `return self` signature bug: ordinary
harvest advertised an instance pointer. The existing all-class-object return
harvest now also recognizes class-method self and emits `singleton(C)`; ordinary
instance self is unchanged. The original stronger direct-return/inherited identity
control is restored and passes natively. Mixed non-class return shapes retain
the existing conservative boundary.

The equivalence claims are different:

- Expression ingest → Ruby emit → ingest checks **IR stability**.
- Whole-app byte-for-byte source round-trip is retired.
- `tests/lowered_ruby_emit.rs` checks lowered structure;
  `tests/spinel_toolchain.rs` exercises native compilation;
  `tests/emit_and_run.rs` exercises emitted Ruby behavior.

A clean analyzer result alone proves none of the last two. Target-only runtime
gaps must remain named; do not claim support merely because another target runs.

### Typed runtime singleton-definition families

`lower::runtime_definition_family` is a shared pre-emission phase for Ruby,
JRuby and Spinel. After original-body analysis, it represents a proven runtime
installation family in `App.runtime_definition_families`, preserves original
installation expressions, and re-analyzes concrete typed entry/slot/bound-method
and state classes. A factory's closure keeps its lexical captures; its installed
method receiver and called/original names become explicit arguments. There is
no stored-Proc self rebinding and no source-owner getter installed ahead of its
actual event.

The first admitted family is deliberately narrow: one plain source root class,
indexed descendants with unchanged parents, a finite source-derived name domain
chosen at runtime, zero arguments, closed primitive/container result types and
compatible class-storage contracts. Installation, alias snapshots, inherited
lookup, visibility, bound receiver/name/original-name/arity/call/equality and the
actual `singleton_method_added` callback execute at their original events.
Unsupported mutation/reflection, escaping Class/Method values, unmodeled frames,
protocol/core overrides, ambiguous domains and incompatible storage retain the
original unsupported boundary. This is not general Ruby method-table reflection,
open provider/YAML name discovery, optional arguments, model/module installation
or the original Discourse settings/security closure.

Two analysis seams carry the real types rather than an untyped bag: literal
callable arguments receive their declaration's parameter types (their body and
return are still inferred), and explicit class-receiver storage accesses consume
source-proven capture contracts. RBS `singleton(C)` retains `Class[C]` identity
through parameters, callable fields and returns; foreign lexical scopes emit an
explicitly rooted owner. Ordinary instance types remain instances.

The runtime follows the closed **source declaration hierarchy**, not unbounded
`Class#superclass` reflection. In measured full-runtime native compilation the
latter widened unrelated dynamic constructor reachability, polluting Flash's
String-keyed initializer with Relation's Symbol-keyed constructor arguments.
The concrete parent capability preserves the admitted unchanged hierarchy; it
contains no observed class-state/config/permission values. No runtime file or
original callback is dropped to avoid that refusal.

`App.library_load_dependencies` records genuine producer load edges. In
particular the source's callback can run when it defines itself, before the
normal model aggregator would load method-only dependencies. The generated
runtime and its concrete classes must already exist then; arbitrary body-only
application imports retain their existing cycle-safe aggregation policy.

Owning controls are in `tests/runtime_definition_family.rs`: original/lowered
CRuby and native runtime-derived name choices, absence before installation,
root/subclass storage and uninitialized-storage errors, live mutable lexical
captures, callback ordering/presence, aliases and Method frames/identity,
visibility, once-only effectful query operands, two families with a helper-name
collision, full-framework boot, and explicit unsupported-shape refusals. Both
runtime helper bodies **and lifted source callable bodies** are checked for
closed types. These compiler prerequisites do not pass strict019 or replace its
actual native original-source/security/PG/negative-control proof.

The next owning extension admits a **typed runtime Symbol/String name** absent
from the program's literals. `open_names` records that distinction in the IR;
no name/value snapshot or eager method expansion is involved. Finite native
names still take their original APIs. Unknown runtime operations use live
family slots; replacement of an existing native method (or a missing family
slot that instead names a native method) explicitly raises NotImplementedError.
That unsupported native-table replacement is not silently approximated by a
virtual slot. Other observer/escape/arity/receiver/storage boundaries remain.
`tests/runtime_definition_open_name.rs` compares arbitrary ARGV names against
original Ruby and native, including aliases, captured entries, identity and
visibility, and checks the runtime refusal. Nullable/non-string names and
conditional invalid-name types retain the original compile refusal.

`fidelity/tools/verify_global_setting_register.py` applies this event family to byte-exact
original `GlobalSetting.register`, its original provider accessor, and complete
original BaseProvider/EnvProvider classes. An explicitly synthetic caller uses
the real EnvProvider (not a replacement getter/provider) and changes only its
own process's test ENV input after installation; later calls must observe it.
This pure projection is NOT configure!, load_defaults/YAML, SiteSetting/plugin
bootstrap, security/PG or ticket019 acceptance. It preserves the less-obvious
original coercion/default rules: false/empty defaults become nil, and an
explicitly empty ENV value suppresses the fallback rather than choosing it.

### Original cached GlobalSetting factory path

The measured next gap was not another name-domain expansion: the original
`GlobalSetting.load_defaults` getter reads/writes `"@#{key}_cache"`. The first
analysis already proves every writer's closed value type (including the
`:missing` sentinel), but its computed read was unknown. Source-proven computed
class-storage contracts now retain **owner + fixed prefix/suffix + closed
write-value type**, never values. A second ordinary analysis closes the
original getter before event admission. Only a plain root runtime producer and
one namespace are admitted. Unknown addresses/writes, multiple namespaces,
incompatible descendant writes and compound namespace mutations retain refusal;
literal/initializer/default writes are checked too. This is not a general
reflective bag. Lifted core storage APIs stay directly on the explicit method
receiver, with every runtime and lifted body still closed. Ruby emission keeps
that explicit receiver instead of respelling it as an implicit-instance call.

Native owning proof independently exposed absent computed **Class-object** ivar
support. Spinel now uses its existing real class-keyed ivar table, not an
instance layout or a fixed declaring class. It does not widen unrelated fields.
Computed names overlapping statically laid-out slots and non-ASCII identifiers
have explicit NotImplementedError boundaries; a possible source class-method
override keeps a compile refusal, while statically bound overrides still run.

`python3 fidelity/tools/verify_global_setting_register.py --cache` executes the
byte-exact original `register`, `add_default`, `configure!`, `load_defaults`,
original accessor and complete Base/ENV/File/Blank providers. The original
`discourse_defaults.conf` is packaged verbatim, parsed by the original
FileProvider using real ERB, and traced as a runtime read. The pinned defaults
has no ERB tags; native ERB's explicit eval refusal remains. Additional owned
config files are created **after ELF compilation** and passed by runtime path.
Twelve original/lowered/native cases prove actual defaults, file versus ENV
provider semantics, cached false/zero/nil, live register replacement and invalid
cache-name NameError. No application method text/getter/provider is replaced.
This selected source closure is **not full GlobalSetting/Rails boot**,
SiteSetting YAML/module/model/optional-argument/plugin/cache-service bootstrap,
User/Guardian/PG security or019 acceptance. The complete original closure stays
unsupported until those independently measured paths really execute.

Remaining runtime-definition warnings retain their original unsupported event and
source span, but now append unproved argument ABI, method-return frame and
unresolved callable-body facts. A computed name by itself is no longer a useful
explanation once a closed typed family can own one. This reporting does not
relax admission or turn unsupported output into executable proof. The actual
complete original SSE1143 event still reports those obligations; the separate
GlobalSetting source proof must not be mistaken for it.

Original-source ABI follow-up: an initial analysis could stamp an inferred
`register -> untyped` before event lowering, then treat its own stamp as an
immutable declaration on reanalysis. Analysis-owned signatures now retain
serializable owner/method/receiver/span/type provenance. The shared family and
storage reanalysis seams forget only unchanged inference-owned stamps, not
source/RBS or new concrete helper signatures. The actual original four public
factory return signatures now close as well as their lifted bodies. An
independent failing-before reduced factory test, explicit author-declared
`untyped` negative and nonempty provenance round-trip guard this distinction.
