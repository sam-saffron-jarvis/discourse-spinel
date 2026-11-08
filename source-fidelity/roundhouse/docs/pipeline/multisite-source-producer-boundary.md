# Multisite producer and member-feature boundary (diagnostic, not admission)

The genuine source's `ConnectionManagement.instance` returns
`@instance || NullInstance.instance`. Its class-owned writers assign nil or
`new(config_filename)`. The original no-plugin oracle happened to return
NullInstance, but that observed choice is not an input or a construction proof.
The typed source keeps `SelfInstance | NullInstance`; the forwarded `current_db`
receiver keeps both main-instance and null-instance arms. The actual configured
instance's `current_db` still reads an unresolved `ConnectionSpecification`
configuration Hash before its DEFAULT fallback. A String return signature alone
cannot close those value/body dependencies.

A bounded return-provenance experiment initially hypothesized that two simple
factory return signatures would have the same nominal Class type. That was
**falsified**, and its raw failed test is retained: the analyzer distinguishes
implicit `new` as SelfInstance, explicit construction as an instance Class type,
and `self`/a class constant as `Class[T]`. Do not add a new type family based on
the stale broad-conflation hypothesis. Some expression contexts still need syntax
provenance; return signatures by themselves are not a source dispatch/writer or
argument-contract witness.

The corrected control executes the distinct source factories under CRuby: the
instance calls its one-argument method, whereas the class object reaches a
same-named class method with a different arity and raises the complete original
ArgumentError. Both factory-based forwards remain source-contract refusals. A
literal local constructor does prove a source destination in the existing
resolver, but it still does NOT grant the unverified native forwarding carrier.
No guard was relaxed, no ABI was borrowed from an observed or asserted type.

The next constructive witness would need the actual source producer returns,
class-owned field writers/aliases, Singleton construction protocol, lookup and
lifetime closure, and compatible source contracts for every reachable receiver
arm. Separately, the real main and freedom-patch MEMBER declarations need distinct
execution feature identities on one class binding. Initializer002's immediate
require and deferred glob/callback are real operations, not a reason to merge or
hoist both class bodies. Current expanded original input is still strictly
rejected. These are source-labelled design boundaries, not native core getter,
query, serializer, controller or page support.

The namespace projection now preserves its refusal while identifying declaration
sources missing from ordered file-program IR. Both the generic app/lib patch
control and the actual audited input name the missing source. This diagnostic
must not be read as a new member-feature admission: no body was merged, no
callback moved, and no executable target is returned for that input.

Two bounded native hypotheses were rejected rather than admitted on compilation:
an all-channel anonymous rewrite reached an unchecked typed builtin packet path
and raised incorrect NoMethodError; class-side dynamic Method lookup exposed
synthetic parameter names instead of the source forwarding descriptor. The trial
patches/output were retained outside the compiler tree, and neither was adopted.
A checked positional/keyword/block packet AND source-backed runtime descriptor
are necessary; return/arity information by itself is not the contract.

The audited original producer assertions run regardless of whether a typed-IR
export path is requested. Exporting diagnostic JSON is optional; retaining every
source receiver arm and the native refusal is not.

## Concrete next fragment representation

The current `FileProgram::Declared(Vec<ClassId>)` and
`Plan::declarations: ClassId -> resource` cannot identify two real member
fragments of one binding. The source parser needs a declaration-site identity
(binding + source file/span + record ownership), independent of the class's
runtime identity. Emission grouping must use that fragment/resource identity,
not concatenate both records under the class's first file. Preserve lexical
headers, each body-end and member-added callback, loader cache and declared
source order. Do not derive a declaration's identity from an observed class or
from whichever record an inferred-type lookup happens to return first.

The new two-member-feature regression keeps both nonempty source records and
proves the original callback/API order under CRuby while requiring the current
single-resource profile to refuse. A separate native source-control experiment
passes for unconditional requires, but conditional require placement remains
unproved. A top-level Class local needed a further source-binding witness to
use the same load-point method history as a constant. The scoped Spinel fix
requires one plain direct program assignment, before the read in the same file,
with no other writes and an elaboration-proved class constant. It does not
certify factories, closures, nullable aliases, constructors or full forwarding.
Roundhouse's namespace value/constructor and member-feature guards remain.
