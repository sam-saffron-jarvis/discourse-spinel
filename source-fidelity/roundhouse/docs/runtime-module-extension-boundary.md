# Source module-extension runtime-definition boundary

The shared `RuntimeExtensionEvent` records an actual source `extend` expression,
its module and its sole proven extender. Module instance producers are typed with
that Class receiver and its class-object storage; module singleton methods keep
the module's own storage. The module, original extend and real automatic
`extended` callback remain executable source. No method is copied onto the owner
and no second callback is synthesized.

The existing closed zero-argument runtime-definition family can consume this
boundary for a plain root with one source extension and an existing hook. Its
typed registry records activation at the start of the real callback (Ruby has
already installed the module's methods then). Producer methods reject calls
before that event, and presence queries respect activation and inheritance.
Original ivar effects and module API calls participate in the shared
`REPLAYED_CLASS_BODY` source-order sequence, alongside initializers and defs.
For example, dropping `@events.clear` or replaying `setup_methods` after later
definitions changes the observable callback history and is not permitted.

Admission remains narrow: required-only producer arguments; closed templates,
module bodies and generated runtime bodies; no custom extend_object, multiple
extenders, module-object escapes, producer Method binding, incompatible calls or
unreplayed class-load effects. The only pre-lowering unknown results admitted
are exact installation events (known Symbol result), their sequence tails, and
zero-argument getter calls with an already-proven typed family replacement.
Explicitly declared untyped hook arguments are not overridden by owner inference.
Lexical Class captures must actually be read by an installation in the same
executable source root; unrelated Class aliases still refuse.

`tests/runtime_definition_module_extension.rs` compares original CRuby with the
same lowered Ruby and a separately compiled native Spinel consumer. It checks
before/after extension presence, an early-call NoMethodError, callback order,
class-body installation, runtime installation, inherited receiver storage,
module/owner storage separation and serialized original-event provenance. The
reduced test's producer and callback arguments are now inferred from actual
class-load/runtime/literal reflective calls, including Ruby's automatic callback
Class argument. The same-slot `@values` on the module and extender has distinct
Integer versus Hash types and runtime values. This is not evidence that original
YAML registration arguments have been inferred. Negative controls keep
the original runtime-defined-method refusal.

Actual-original reapplication is mandatory. On the attempt7 boundary checkpoint,
the unchanged full original SiteSetting/SiteSettingExtension inputs still refuse
SSE line1143: optional-argument ABI, 57 unresolved callable-body nodes and method
return frames. The reduced boundary is a prerequisite, not native settings boot,
provider/plugin/YAML registration, security getter, Guardian or ticket019
acceptance. Unsupported original diagnostic output is never executed.

The argument follow-up routes a folded owner class call to its original module
instance definition, retaining keyword placement and excluding own definitions or
competing modules. Literal builtin send/public_send sites forward argument types;
user overrides and their ancestry do not. The implicit Object installation result
is Symbol, which exposed a pre-existing signature-stamping defect: source/RBS
contracts held in App must be attached before inference stamps MethodDef, including
explicitly untyped returns. Those declarations remain authoritative.

Original reapplication after this argument work still reports 57 unresolved
SSE1143 body nodes. Actual `load_settings` now has a String file parameter, the
real extended hook has a Symbol-or-nil return, and several original API parameter
rows improve. No YAML registration/storage/security closure is implied.

The storage follow-up recognizes the actual simple memoized-reader shape
`def themeable; @themeable ||= {}; end` and collects index writes through that
reader in its proven owner context. Module instance ivar writes belong to the
extender. The empty seed has no elements and is rebuilt from current source
writers, not its old inferred annotation. Unknown keys/values remain debt;
wrong-owner and non-memoized readers do not borrow this evidence. The existing
empty-container expected-type propagation now also applies at ivar `||=`.

Original SSE `themeable[name] = opts[:themeable] ? true : false` closes its reader
to Hash[Symbol, bool]. The unchanged SSE1143 diagnostic falls from57 to55 unknown
body nodes. Plugins and mandatory-values keys improve, but their values remain
untyped; current/theme-site values and optional argument/return-frame contracts
are still open. Native/lowered/original reduced controls pass, including a
runtime getter that calls the real memoized module reader and inherited storage.

The original plugin producer has a separate measured typing prerequisite:
`Plugin::Instance.find_all` builds `[].tap { |plugins| ... plugins <<
parse_from_source(path) }`. Its parsed element already typed Plugin::Instance,
but the empty receiver and returned Array kept an unresolved element. The shared
body typer now derives only this empty-array receiver mutation contract and
retypes the unchanged block. It does not use the block's discarded return.
Unknown writes, parameter rebinding/escape/shadowing, escaping tap break, and
source core/include overrides retain an open result. The reduced original,
lowered and native programs agree and every reduced method body is closed.

Actual original find_all now returns Array[Plugin::Instance]; this is not plugin
activation/configuration or original settings boot. Original Discourse's plugin
registry still carries an untyped value arm, and SSE1143 remains at51 unresolved
body nodes on the expanded whole-dependency diagnostic. Getter/security refusal
is retained. Whole-source acquisition is recorded separately in Fidelity.

The source yield follow-up collects every positional yield tuple in one method
frame, including ordinary nested blocks but excluding nested defs. It preserves
unknown arguments/consumers and fills missing positions with nil; splat/forwarded
shapes do not get a partial inferred contract. Partial container shapes remain
partial, and empty literals supply no fictitious element witness. Actual direct
consumers can supply a block-result type; reflective/escaped/rebound/unknown
consumers retain return debt instead of borrowing another block's result.

The ordinary return fixpoint carries these contracts, folds them through the
existing owner surfaces, and serializes the inferred block ABI. Pending wrapper
params cannot freeze later observations, and source/RBS declarations stay
in charge. Each body typer keeps its lexical method's implicit block even under
ordinary iterators. Callback effects remain opaque/impure; typing a tuple never
licenses dropping a yield or callback.

A four-value source-loader/consumer reduction has fully closed bodies and passes
original Ruby, same-lowered Ruby and native Spinel. Collector/frame/authority/
reflection controls and the global fully-typed-runtime invariant pass. The actual
original YamlLoader now retains its four-argument block shape in shared IR, but
its YAML-produced values/default/option entries and consumer return remain open.
No resource schema/value snapshot, plugin omission or typed-getter admission was
introduced. Original SSE1143 still51unknown nodes plus optional ABI and return
frames; the mandatory actual-source strict gate remains nonzero.


The next actual producer defect was an inferred empty singleton Hash seed
surviving later reset/populate writes. The shared analysis now rebuilds only
simple source singleton memoized Hash readers from their current writers and
keeps class-object state separate from instance flow, even when both use the
same ivar spelling. Unknown values, unproved mutators, reflective writes,
receiver rebinding and table aliases/escapes remain unresolved debt. No source
values or plugin configuration are supplied by the compiler.

A reduced plugin registry now has fully closed helper bodies and original,
lowered and native parity. Its instance marker is Integer41 while the class
registry contains actual PluginDescriptor instances; the missing-plugin lookup
retains nil and raises NoMethodError when called. The stronger control exposed
a native seed ownership defect: Spinel's container-reader seed pinned shared
ivar metadata across physically distinct class/instance stores. The native fix
keeps mixed-home backing storage boxed, preserves the seeded home's empty
container payload layout and the existing checked boxed-return contract, and
checks statically contradicting writes only in the reader's own home. Native
Hash/Array and wrong-writer controls, the full native RBS seed suite and four
GC-stress/sharing/integer-mode combinations pass. Explicit conflicting field
annotations and arbitrary reflective writer inference are not newly claimed.

Actual Discourse.plugins_by_name now has Plugin::Instance-or-nil lookup values,
and configurable? is Bool. Its key type and enabled_site_setting configuration
remain open: the captured source has no concrete setter call for the latter.
The actual SSE1143 getter diagnostic improves from51 to46 unknown body nodes,
but still refuses the optional callable ABI, unresolved body and method-return
frame. Strict019 remains nonzero; this is not original settings boot, getter,
security or direct-PG acceptance. Unsupported diagnostic output is never run.


The whole original Metadata producer exposed two additional, separate gaps.
Ordinary library `attr_accessor(*FIELDS)` now expands the source's finite
literal list rather than silently omitting every accessor. It reuses the model
constant folder's mutation/alias taint, additionally requires the constant to
precede the call and declines unknown/mixed/invalid splats as a whole, retaining
the original call. Existing direct Symbol and cattr/mattr behavior is preserved.

Core String#each_line yields String and returns its receiver on normal block
completion; escaping breaks contribute their actual value types. Nested block/
loop breaks do not replace that outer result. Blockless/unknown/overridden
iterators remain open. Parameter observations now mirror dispatch's existing
base-surface substitution for an instance a class-side `new` creates, without
erasing its late-bound SelfInstance type. Unproved rebound-self block origins
supply no such observation, and declared gradual parameters stay authoritative.

Reduced finite accessor and Metadata-shaped parser programs have fully closed
helper bodies and original/lowered/native parity. The unchanged actual
Plugin::Metadata.parse text and parse_line line parameters are now String, and
its original accessor declarations are present. Getter values remain open:
the computed public_send setter still has no closed writer argument routing.
This is not typed plugin configuration or settings boot. Actual strict019 was
immediately reapplied and still refuses SSE1143 with46unknown body nodes, plus
the optional callable ABI and method-return frame. No unsupported output ran.


A further original plugin path gap was not missing Dir/File signatures: Dir[]
already returns Array[String]. Plugin::Instance.parse_from_source instead calls
implicit `new(metadata, path)`, while parameter collection previously forwarded
only constant-receiver new arguments to initialize. Proven builtin implicit/
self Class#new now contributes those actual arguments to its real initializer.
The expression keeps SelfInstance, defaults keep nil, source constructor
contracts stay authoritative, and custom/inherited new or unproved descendant
initializers do not acquire a builtin observation. No constructor is synthesized
and no object/field name or application byte is changed.

The original Plugin::Instance path getter now has String|nil and metadata has
Plugin::Metadata|nil, derived from the actual Dir/File/parser/factory producers.
Enabled-setting configuration and Metadata computed setter values remain open.
A reduced source factory has fully closed bodies, original/lowered/native parity
and nil-default/constructor-override controls; the never-executed whole-original
input confirms both improvements and still refuses the original settings family.
The mandatory strict gate remains at46unknown getter-body nodes; optional ABI,
return frames and actual settings/security execution are not claimed.


The implicit-constructor observation also stays disabled for an open or
source-overridden global Class#new, including known mixed-in new methods.
An explicitly passed unknown argument remains unknown instead of becoming the
optional nil default. The valid optional source RBS declaration is asserted to
be present before testing its gradual authority; initialize intentionally need
not have an inferred MethodDef signature, so its actual typed assignment body
is the constructor argument evidence. Existing constructor and inheritance
controls pass alongside all native/full-framework family consumers.


Final measured Metadata follow-up (superseding the computed-writer debt above):
the source `attribute, *value = line[1..-1].split(":")` desugared to a nested
statement sequence whose local tail was not visible to the following statement.
Shared ingest now splices only an unadorned, statement-position multi-write
sequence into that same local scope. RHS evaluation, target order and the
assignment's result remain the existing desugar's; semantic/ascription wrappers
are not flattened. No application bytes or source values are substituted.

A builtin computed `public_send("#{attribute}=", value)` supplies its actual
argument type to possible known source writers of a closed root. This is a
conservative parameter observation, not selector-domain admission or a dispatch
rewrite. The original call, argument evaluation and effects remain intact.
Unknown values/selectors, source reflection or method_missing protocols,
inheritance/descendants, implicit Object writers and declared gradual setters
retain debt. A typed ActiveSupport namespace stamp keeps truncate lowering from
introducing an untyped leaf after the source parser was typed.

All21 actual Plugin::Metadata method bodies are now closed in the whole-original
never-executed diagnostic, including name String|nil and Integer-or-nil topic ID
conversion. A reduced source parser agrees original/lowered/native and verifies
conversion, one real dispatch and write order/count. This does not prove its
resource/class-load boot or plugin activation. Enabled-setting configuration,
YAML/default/current/theme/provider/enum values and the original getter ABI/frame
remain open. Actual strict019 immediately reapplied still refuses SSE1143, now
**45unknown nodes** (59 before this recovery), and Guardian273 has no original
native getter. No original security/direct-PG019 or /latest acceptance is claimed.
