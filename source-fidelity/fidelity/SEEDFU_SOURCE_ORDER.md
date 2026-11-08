# Cold SeedFu source-order obligations (Recovery11)

This is a bounded prerequisite design and set of original-source controls, **not
native SeedFu, plugin activation, full-registry/query, or SAME019 acceptance**.
The original application and gem bodies are not replaced. Values observed at
Rails boot are never native inputs.

## Executable original-macro controls

```
source ../harness/env.sh
BUNDLE_JOBS=4 taskset -c 0-3 ruby test/mattr_source_order_test.rb
```

The controls load the complete installed ActiveSupport 8.1.4 attribute-accessor
source only after checking its previously package-verified member SHA-256. The
six tests observe the original methods, core calls and definition hooks; they
never wrap or replace those methods. Reduced test subjects are not application
classes or runtime availability stubs.

Facts the event representation must retain:

1. For a multi-name reader, storage for **all** names is seeded before any class
   or instance reader is installed. Definitions are then class/instance pairs
   in argument order. The writer repeats the storage phase, then installs its
   class/instance writer pairs. An accessor calls reader before writer.
2. Nil seeds check existing storage and preserve it. A repeated declaration
   still reinstalls the methods and fires definition hooks: deduplicating the
   generated methods is not equivalent to deduplicating storage initialization.
3. Generated class and instance methods are public even under a private caller.
   Arity, shared storage/identity and caller source filename are observable.
4. The accessor forwards its block **only to its reader**, not to its writer.
   A nil-default writer therefore preserves the block's stored value. A
   non-nil keyword default is evaluated once as a call argument but passed to
   actual storage calls in both reader and writer phases, with the same object.
5. `class_variable_set` is a real overridable protocol call. Replacing it with
   bare `@@` assignment removes observable effects. A future finite profile
   must carry the actual call or prove/refuse an overridden world; literal RHS
   purity is not that proof.

An initial experimental assertion wrongly assumed the accessor forwarded its
block to both phases; the original source disproved it. The failed log is
retained (`recovery11-real-mattr-order-initial-wrong-forwarding.log`). No
framework source or expected native result was changed to accommodate it.

## Independent native file-program boundary

The shared leading-autoload fix is necessary, but its emitted-Ruby controls do
not prove native loading. The bounded clean source-gem bootstrap measurement in
`build/recovery11-native-source-bootstrap` uses the actual generated files:

- CRuby's generated file-program tree sees the registration from the carried
  module body and loads the autoloaded value correctly.
- Compiling that **unchanged** generated bootstrap with native graph loading
  fails at `app/models.rb:38`: `unresolved autoload owner`. The exception path
  restores an autoload through a dynamic `scope`; even a successful ordinary
  load does not license discarding that path.
- Plain Spinel output currently does not call `apply_file_programs` at all. It
  eagerly lists the declarations and drops the leading registration. It is not
  an alternative proof of the original load/cache/effect semantics. Its warning
  output was not compiled/executed as a successful native substitute.

This is a measured unsupported native bootstrap profile, not a proven Spinel
bug. No Spinel source was changed, no graph guard weakened, no failure/retry
path deleted, and no errorful SeedFu output executed. The earlier reduced native
lazy-autoload primitive control does not cover this dynamic-owner helper.

## Shared-IR design boundary for the next implementation

Existing `DeclarationStep { call, ordinal }` can carry ordered macro events
without fabricated source offsets. A complete implementation still needs:

- source-positioned seed/check/protocol-call events, followed by distinct
  class/instance definition events, rather than an alphabetized synthetic tail;
- all repeated definition events, public visibility and original source origin;
- retained defaults, captures, argument evaluation/identity and definition hooks;
- ordering against genuine leading autoloads, requires, other body statements,
  feature/cache identity, exceptions and retries;
- a proved finite native file-program lowering, or an honest refusal before
  execution; do not just enable the CRuby reflection helper on Spinel;
- the real Railtie initializer and every later fixture-path producer. Neither
  the two initializer paths nor the observed thirteen-path array is a seed.

The existing class-side-only mattr abstraction and its explicit source-order
refusal remain unchanged. There is no literal-only commutation waiver, fake
Rails::Railtie/HIA/Class/version, frozen settings, omitted callback, or admission
based on a smaller diagnostic count. Unreached Runner/GzipReader remains outside
the measured cold dependency rather than becoming a distraction to port.

## Recovery12 finite native feature capability (Nov5)

Prerequisite A now has an executable **bounded** profile, not an admission of
cold SeedFu or the Recovery11 dynamic `scope.autoload` helper. The new shared
Roundhouse plan resolves literal owner/resource identities, retains source
file-program events and ordinary lowered bodies in ONE canonical feature, and
lets the native graph loader own cache/rollback/retry. It does not erase the
exception-restoration path, enable the reflective helper, or use the former
plain/eager output as a substitute. See Roundhouse
`docs/pipeline/native-file-programs.md` for the supported/refused contract.

Local source checkpoints:

- Roundhouse **b8679a26e**: finite plan/lowering, exact source-query admission,
  namespace-dominance/lexical qualification and honest refusal worlds.
- Spinel **165659a81**: independently reproduced failed autoload AFTER a class
  definition previously left that binding present, bypassing retry. Roll back
  only the autoload's own binding; ordinary require retains partial definitions.
- Spinel **78f4cf345**: a literal absolute require must resolve as the same
  physical feature as the autoload target and require_relative, not as an `-I`
  library name.
- Spinel **c6d2bb3b5** and **a7f0959a8**: settle deferred literal compact-header
  ownership without moving presence events, reuse the existing unique owner
  candidate proof, and reject a nested leaf through the wrong owner. A focused
  corpus exposed a builtin compact-member regression; retained RED evidence
  led to owner-aware builtin membership, not restoring a blanket exemption.

Reproduce/retain the canonical capability suite (no DB/oracle/service involved):

```
source ../harness/env.sh
python3 tools/probe_native_file_programs.py
```

The canonical Roundhouse suite has **11 passing tests**: original reduced source
vs SAME lowered CRuby/native ELF, lazy/unread effects, registration before body,
qualified lexical constants, repeated/circular require, failure after class
definition, pending binding after failure, retry, and absolute/relative/cache
identity. Refusals cover missing/dynamic/changed resources, owner protocol
replacement/rebinding/missing dominance, reflection, opaque initializer callback,
unpositioned mattr and unproved fresh-Class state/escape. Original and lowered
Ruby files are compared before/after execution. This does not prove arbitrary
Class identity allocation on retry: those worlds refuse. Native graph guards
remain intact.

Exact committed-head capability evidence:
`build/probe-native-file-programs-20261105-045424/evidence.json` contains all
source/artifact hashes, raw original/lowered/native output and a direct ELF
process trace (no Ruby/helper child). The source subjects are reduced compiler
TESTS, never replacement application classes. Full graph suite PASS; focused
namespace/alias corpus71PASS after correction; new exact/wrong builtin-owner
control2PASS. Roundhouse adjacent suites23PASS,5preexistingignored. These are
focused checks, not the full Spinel gate or whole Roundhouse CI.

Fresh committed release SHA:
`5835d103f20a59e771ca4674e32fe2ae0734440c01ea14c3e5101eaecdfa3b1f`.
Actual source reapplication remains deliberately unsuccessful:

- `build/probe-seedfu-closure-20261105-045357`: actual cold observation, real
  Railtie initializer/all live fixture producers and retitled Vips worker
  cleanup/hash audit. MEASUREMENT ONLY, no native SeedFu/seed invocation.
- `build/probe-original-query-20261105-045410`: actual activation935
  String#instance_eval gap, fullquery69errors/unexecuted and the original
  untrimmed constructor/plugin-option mismatch remain failures.
- Existing genuine original macro6tests/29assertions stillPASS. Prerequisite B
  has NOT been implemented; the mattr/@@ ordering refusal is unchanged. The
  finite loader explicitly refuses unpositioned macro events, rather than
  laundering the old class-side-only abstraction into native support.

The failed release reapplication at043228/043229 is retained too: the existing
provenance guard correctly required rebuilding Spinel after its local commits.
Rebuilding, not weakening that guard, enabled the later exact-head measurement.
No private writablePG reuse/copy, shared state writes, fake availability/classes,
frozen observed path array, omitted callback, or global gradual ceiling change.

Next falsifiable experiment is the genuine mattr ordered protocol and paired
class/instance-definition IR under the six original-source controls. A green
loader capability alone cannot accept SeedFu, Railtie effects, plugin activation,
original security/query matrix, F2 or page rendering.

## Recovery12 ordered plain module protocol checkpoint (Nov5 06:12)

Roundhouse **2515abdf0** adds a bounded shared-IR path for a module's literal-name,
absent-default mattr/cattr. Real `class_variable_defined?` / `class_variable_set`
calls run for ALL names before the batch of public class/instance reader defs;
writer repeats its storage phase before its own paired definitions. Every seed
and definition has an original call span and distinct DeclarationStep ordinal.
Source `@@` assignments retain their positions. Repeated definitions survive
under lowered CRuby; the native redefinition guard is NOT waived. Keyword/block
argument/capture identity is NOT yet implemented/admitted. Ordinary class/model
macros retain their old route. See Roundhouse
`docs/pipeline/ordered-module-attributes.md` for the precise contract.

The protocol is not replaced with bare@@: a finite source storage override
executes and sees fresh mutable String names. A second source override that
returns without storing does NOT receive an invented nil assignment. Original
hash-pinned ActiveSupport8.1.4 versus lowered CRuby proves the plain profile;
two separately invoked native tests prove the actual lowered/RBS trees with
storage callbacks and the nonwriting override. They are reduced TEST subjects,
not fake application/framework classes.

### Independently measured native state gaps

- Spinel **ce91541d9**: inherited Module storage `super` is an existing native
  subset limit, but a valid override previously compiled and raised a false
  NoMethodError. It now explicitly refuses the inherited builtin-super world;
  no builtin-super implementation or override bypass was added.
- Spinel **397ba4e25**: one guarded finite literal-name proof handles fresh
  builtin String copies consistently across self lowering, declaration,
  emission and assigned-flag discovery. Overridden String-copy worlds refuse,
  including after a prior literal fold. Actual override arguments remain
  fresh mutable Strings (type/mutation control), not Symbols/frozen literals.
- Actual protocol nil writes were ignored in Bool/Symbol slot inference,
  collapsing observable nil into false/empty Symbol. Use the existing native
  nil-write widening policy for the real protocol store as for direct source
  writes. Original/native nil-before-false and nil-before-Symbol now agree.
- A writer's declared metadata slot was mistaken for an assigned cvar on a
  direct read, even when the actual storage override declined the write.
  Direct reads now check the actual runtime assignment flag; a real later
  writer sets it. No synthetic availability/storage is introduced.

Raw REDs and changed diagnoses remain in `build/recovery12-mattr-protocol` and
`recovery12-ordered-mattr-native.log`: missing builtin super, fresh-name refusal,
missing assigned flag after first name-proof attempt, nil/false mismatch,
nonwriting-with-writer mismatch and overridden-copy mismatch. The final cvar
corpus38PASS, complete graph suitePASS, reject suitePASS. The unrelated
`name.class.name`/later mutation alias failure is retained as
`unadmitted-class-name-alias.rb` and the initial cvar corpus log; this checkpoint
uses direct is_a?(String)/mutability controls and DOES NOT claim that unrelated
reflection surface was fixed.

Roundhouse finite suite **12PASS**, ordered plain suite **4PASS+2nativePASS**;
adjacent class/module/storage suites23PASS with6preexistingignored. The integrated
finite case observes nil immediately after macro installation, BEFORE the actual
source assigns false, and still proves lazy/cache/circular/failure/retry with
original reduced source and SAME lowered CRuby/native files.

Exact committed capability evidence:
`build/probe-native-file-programs-20261105-061137/evidence.json`, including both
artifact snapshots, actual source/file hashes and direct native process proof.
Fresh release SHA:
`b0af0e1a036673cdf8be6c02c730165b0097530de2aa45e3a047c1972d46799e`.

### Actual source failures remain failures

`build/probe-seedfu-closure-20261105-061110` observes the genuine cold require,
Railtie initializer and all13live producer paths with ownership/cleanup/hash
checks, but native SeedFu remains UNADMITTED. The earlier candidate measurement
052707 got past the old source-order error through actual ordered plain events,
not a literal waiver, but was still errorful/unexecuted. The final conservative
macro-world validation refuses the original input's reopened module contexts
(and requires separate effect proof). The strict command is NONZERO; its raw
late ingest error is preserved even though the line-diagnostic extractor returns
an empty array. That is NOT zero-error support or permission to port the
unreached Runner/GzipReader to reduce a count.

`build/probe-original-query-20261105-061124` stillFAILS activation935,
fullquery69errors/unexecuted and the exact untrimmed constructor/plugin-option
mismatch. No observed values were replayed. Actual Railtie/all live producers,
full mattr default/capture/repeated-native semantics, native cold/plugin boot,
original security/query matrix and F2/page remain unfinished. No global gradual
ceiling change or source/graph guard weakening. Continue with a bounded proof of
the precise next unsupported context, never silently drop callbacks or freeze
paths/settings.

## Recovery12 guarded keyword identity / measured block refusal (Nov5 06:56)

Roundhouse **805b75b07** adds a source-positioned, once-only `default:` argument
capture for the ordinary module profile. The evaluated value lives in a hygienic
lexical local chosen against the actual source parse. Both reader and writer
storage calls receive that SAME live argument; they do not reread the cvar cell,
which a real definition hook can replace between phases. No visible synthetic
constant/class ivar or frozen snapshot is added. Declaration-event local TYPE
facts flow forward in a fresh environment per analysis pass; ivar/cvar VALUE
facts do not. The runtime fully-typed-method invariant stillPASS.

Canonical controls now8PASS (+3separately invoked native controls); source
hygiene, macro/core replacement, local/method reflection and block boundaries
have explicit controls. Original AS8.1.4 and lowered/native keyword control:
constructor runsONCE; source storage override calledTWICE; both retained mutable
arguments share identity; the real definition hook replaces the cell; writer
still seeds the original captured argument; later getter mutation reaches both
retained arguments. Adjacent declaration/lifecycle/runtime and finite feature
controls31PASS,6preexistingignored (`recovery12-keyword-final-regressions.log`).

Exact source/artifact proof:
`build/probe-mattr-keyword-20261105-065511/evidence.json`. Reproduce with
`python3 tools/probe_mattr_keyword.py`. It archives the canonical original subject,
genuine macro member path/hash, SAME lowered CRuby/native files and sidecars,
raw commands/results, unchanged Ruby hashes and direct native ELF process trace.
The first runner attempt065222 preserved a legitimate unrelated entry failure:
full generated boot loads native-only SQLite FFI, so CRuby cannot call ffi_lib.
The corrected experiment uses one NEW TEST CONSUMER requiring the library model
aggregator for BOTH engines and freshly compiles that unchanged tree; it does
not edit/drop any generated application/runtime body or claim full boot parity.

Fresh release SHA:
`59d79b84a2cb2482d9c71620732556556fd66f8cd7a194e2d72c74c28973f99e`.
Actual source reapplication **probe-seedfu-closure-20261105-065334** remains a
measurement-only actual cold/Railtie/13producer observation with cleanup/hashes;
strict native candidate stillNONZERO at unproved reopened module context.
**probe-original-query-20261105-065348** stillFAILS actual activation935,
fullquery69errors/unexecuted and the untrimmed constructor/plugin-option result.
No values/settings/path array replayed; no native SeedFu or broader019 admission.

### Changed diagnosis for the remaining block control

`build/recovery12-mattr-captures` retains bounded original and proposed lowered
controls. A hygienic local keyword prototype passed original/prototypeCRuby/native.
A preserved literal-block frame then hit a native implicit module instance_methods
subset refusal. Qualifying that owner did NOT solve semantics: native observed
`[[true, true, false]]` before definitions, original `[[false, false, false]]`.
The observed version is retained with raw stderr/runtime failure, not an assumed
result. This is actual premature method-surface availability. No constant false
availability, callback deletion or blanket module/class presence admission was
used. Module block defaults now explicitlyrefuse before execution rather than
quietly taking the old class-side-only abstraction. Keyword captures also refuse
unproved method/lexical reflection worlds. Finite-autoload default composition
and native repeated-definition admission retain their old boundaries.

Thus the full original six-test mattr matrix and actual native cold SeedFu are
STILL unfinished. Next falsifiable prerequisite is proper ordered module method
surface/repeated definition proof or a source-proven finite context, not another
blind compile or an unreachable gzip/native helper campaign. Existing global
gradual936>920 is not relaxed. All original failures, authority/CPU/deadline
limits, real Railtie and live producers remain binding.

## Recovery13 source-backed repeated accessor checkpoint (Nov5 07:40)

Roundhouse **1982be877** completes retained attempt12 WIP with a deliberately
narrow native identical primitive accessor reinstallation proof. Nonempty
sources/shape are NOT provenance: emit revalidates the closed module world and
checks the registered original source's owner, direct receiverless literal
mattr/cattr call, span, precise side/name/ordinal and primitive cell. Root module,
absent-default repeated calls only; no general method replacement waiver.
Classes, reopens, ancestors (including source includes folded out of IR),
changed macro/core protocols, changed bodies, synthetic/stale events, wrong
owner/ordinal and method-object/surface observations do not get the exception.
Direct generated-accessor calls from application bodies also refuse: identical
final bodies cannot justify pre-definition availability. Original storage calls
and every public class/instance definition/hook stay, not deduplicated.

Exact committed original/SAME lowered CRuby/native proof:
**build/probe-mattr-repeat-20261105-073711/evidence.json**. Reproduce with
`python3 tools/probe_mattr_keyword.py --case repeat`; original subject hash,
hash-pinned genuine macro, unchanged generated Ruby, RBS hashes, ELF/process
trace and all commands retained. Reinstalled BOTH sides preserve public
visibility, identity, reader/writer mutation, event order/counts and storage
retention. Keyword identity regression alsoPASS under the same compiler:
**probe-mattr-keyword-20261105-073843** (`--case keyword`). Neither loads framework
boot or proves native cold SeedFu; one new common library consumer is used in
both engines without editing any generated runtime/application file.

Relevant regressions: ordered profile12PASS/4native separately, class-instance
state12PASS/2ignored, runtime classvar3PASS/1ignored. Full runtime test9PASS/1FAIL:
fully-typed invariantPASS, existing global gradual936>920FAIL retained. NO ceiling
or diagnostics relaxation. Initial ancestor-negative harness classified an
include-bearing source file out of library_classes; it was NOT a source execution
proof. Final ancestor negatives use the actual retained module IR/source and
assert native refusal at emission, including post-ingest changes.

SAME019/F2/page remains UNFINISHED. Next immediate action: committed release
reapplication of actual cold SeedFu/real Railtie/all live producers and original
activation/fullquery/untrimmed constructor. Then a source-labelled experiment
on the precise original reopened module context or real block timing, never a
new unrelated capability family. All endpoint/human/CPU/deadline restrictions
remain; no helpers or consumed private PG fixture reuse.
