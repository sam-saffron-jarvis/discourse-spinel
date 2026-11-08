# Ordered plain module attributes

`ingest/ordered_mattr.rs` is a bounded Module#mattr/cattr event profile. Ordinary
class/model accessors, defaults/blocks and singleton/class-method contexts retain
their prior path/refusals; this is not a general replacement for ActiveSupport.

For a literal-name module declaration with the absent (nil) default, the shared
IR now carries the actual storage protocol and both method sides:

1. For every name, call `class_variable_defined?` and, if absent, actually call
   `class_variable_set(name, nil)`. This is not a bare `@@` assignment.
2. After ALL reader seeds, install each public class/instance reader pair.
3. A writer performs its own complete seed phase before its public
   class/instance writer pairs. An accessor invokes reader before writer.
4. Every initializer and definition carries `DeclarationStep { call, ordinal }`.
   The call is its real source span, never a fabricated offset. Ordinary source
   `@@` writes retain their own position among those events.

Storage-set overrides execute. Names are fresh mutable Strings as in the real
interpolations, not Symbols/frozen shared arguments. An override that declines
the write must not receive invented initialized storage. Nil preservation is
separate from definition retention: lowered CRuby reinstalls both method sides
and their hooks on a repeated declaration.

## Boundaries

The current profile requires one ordinary module declaration context and an
unmodified macro/core world. Reopened contexts, includes/ancestors, opaque owner
body calls, reflective mutation and source changes to the macro/module_eval or
String-copy protocol refuse. This is deliberately conservative. A storage-set
override alone is NOT refused or replaced by the builtin.

Native repeated-definition admission has the narrow source-backed identical
accessor exception below. The full original six-control matrix and block
defaults are not claimed by this profile. The old
unpositioned-default/include ordering guards remain. No literal-commutation
waiver or global native/gradual diagnostic relaxation is involved.

A native override whose `super` reaches Module's storage primitive remains an
inherited-builtin-super subset limitation; it now refuses rather than raising a
false NoMethodError. Finite explicit source overrides and real builtin storage
have executable native controls. Neither proves arbitrary dynamic storage names.

## Verification

`tests/ordered_mattr_events.rs` compares genuine hash-pinned ActiveSupport8.1.4
against lowered Ruby for seed/definition callback order, public methods, shared
class/instance identity, repeated hooks and an actual nonwriting override. The
separately invoked ignored native tests compile/run the unchanged output with
its RBS sidecars and no external service. `tests/native_file_programs.rs` also
compares original/SAME lowered CRuby/native with an observed nil seed BEFORE an
explicit false assignment, composed with lazy require/autoload, failure and retry.

This is prerequisite progress, not native SeedFu or Rails initialization. The
actual Railtie initializer, all live fixture producers, plugin activation,
original query/security matrix and /latest must still execute. Observed boot
values are never seeds; an unreachable gzip candidate is not ported to reduce
an error count.

## Guarded keyword arguments

A module's `default:` call argument can now be evaluated once into a hygienic
lexical local, before either phase. Both reader and writer storage calls use
that SAME live value. This is not a class-variable reread (a definition hook can
replace the cell), a frozen snapshot, or a visible synthetic constant/class ivar.
The existing parsed-source reserved-local utility chooses the name. Declaration
initializer typing carries only the temporary's type forward; each typing pass
starts a fresh local environment and never exports ivar/cvar value facts.

The keyword control compares genuine hash-pinned ActiveSupport with lowered
CRuby/native. Its argument constructor runs once, actual storage overrides are
called twice with the same mutable object, a real definition hook replaces the
cell between phases, and writer still reseeds the captured argument. Mutation
through the getter is observed by both retained protocol arguments.

This keyword route deliberately refuses lexical reflection and unproved
method-surface observation. It does not admit defaults in the finite autoload
profile yet: exact default-site/resource/error/capture composition still needs
its own control. Block defaults are explicitly refused for module ingestion,
not silently sent through the old class-side-only abstraction. A bounded native
prototype preserved the block but exposed method-table timing: before the defs,
respond_to?/instance_methods observed `[true, true, false]` where original Ruby
observed `[false, false, false]`. Qualification alone is NOT a fix. No fake
availability value or method-table/graph guard waiver is permitted. Full original six-control admission remains unfinished.

## Repeated identical native accessors

The native redefinition guard accepts only identical primitive readers/writers
from literal, absent-default mattr/cattr calls in one root module body. This is
not general method replacement. Emission revalidates the application world,
then parses the registered original source (read-only): owner, direct receiverless
macro call, span, exact ordinal, name, receiver and primitive cell must agree.
A nonempty source registry or accessor-shaped body alone is not provenance.
Source includes are checked too, even if a previous pass folded them away.
Reopens, classes, ancestors, changed core/macro protocols, aliases, unsupported
formals, synthetic/stale event locations and changed bodies do not get the proof.
Repeated keyword/default declarations are not admitted by this exception.

Every real seed and paired public definition remains, including every callback.
No synthetic storage replaces class_variable_set. The executable test compares
original ActiveSupport, SAME lowered CRuby/native, event order/counts and both
reinstalled method sides' public visibility and shared mutable identity.
Method objects, method-table reflection and direct calls to generated accessors
in application bodies are conservatively refused for this repeated profile:
even an identical final implementation is not available before its first def.
This refusal is not a fake availability query or a timing implementation.
