# Runtime singleton callable families: nil-optionals and return frames

`lower/runtime_definition_family` still admits only closed typed source-owned
families with their existing receiver/storage/reflection guards. Original
installation events create registry entries at runtime, including every actual
definition callback, aliases, replacement identity and bound-Method snapshot.
No future native method is exposed ahead of its event.

A narrow additional invocation profile supports literal nil-default positional
formals when EVERY admitted invocation supplies zero source arguments. Required
arguments, keywords, rests, nonnil/computed defaults and explicit arguments
remain refused. This is not a general optional-argument dispatcher. Original
method arity is stored per entry: zero for the old shape, -1 for nil-optionals;
bound aliases/snapshots report that source arity, not the helper closure ABI.

The optional parameters remain REAL formals of the lifted callable, after its
explicit receiver/called-name/original-name metadata. Replacing them with local
assignments would capture and overwrite a same-named factory local, changing
closure identity/effects. The executable control retains a same-named live
factory capture, changes it after installation, and verifies later calls leave
it intact. Reserved helper-parameter collisions refuse before rewriting.

A method-body early `return` can stay inside that callable's lambda frame when
the source callable has an otherwise closed inferred result. It returns from
the installed method invocation, not from its already-returned factory. Other
unproved control-frame operations (yield/super/break/etc.) retain their guard.
No inference sites are replaced with untyped containers or relaxed ceilings.

This work was motivated by the actually observed FIRST original core /latest
setting reader's `|scoped_to = nil|` and early returns. It proves that specific
language-core prerequisite against original/SAME lowered CRuby/native, with
installation callbacks, inheritance, mutable captures, method names, arity,
aliases and replacement. It does NOT implement or admit SiteSetting's original
provider/YAML/refresh/cache/core bootstrap; its unresolved types and model
receiver ownership still require separate proof. Native original core query,
serialization/controller/document and full/plugin019 remain unaccepted.

## Direct ActiveRecord model class owners

The same shared family pass can now use a source model's class object as its
owner. The shared model-to-library projection is an analysis-only view for
class storage/constants and native method-name collision checks. The real model
stays in `App::models`, retains its original superclass/table/associations, and
is emitted once. Model methods and declaration expressions are rewritten with
class-versus-instance context before the remaining shared executable walk.

This narrow owner profile requires a single top-level source declaration,
direct `ActiveRecord::Base` parent, no reopens, descendants, competing model or
AR-base definitions, or unproved class-body effects/mixins. The provenance check
reads the registered source as well as IR: primary-model ingestion alone would
miss a second declaration in the same file. Existing typed-template,
reflection/observer, invocation and storage guards still apply. An empty hash
class-body seed joins concrete class-method writes using the existing
container-aware ivar-slot join, not a union retaining pending element types.

The pure class-object control executes original installed ActiveRecord, SAME
lowered CRuby and native Spinel, with both runtime-selected names, mutable
captures, optional-formal shadowing, definition callbacks, native query/table
method presence, table identity, bound receiver and original arity. It performs
no database operations. Reopen/subclass/arbitrary-parent/opaque-body/mixin and
native-method collision negatives remain refused. This is a reduced compiler
capability proof, NOT admission of SiteSetting's larger extension, metadata,
provider or refresh/bootstrap closure. The actual first core getter remains
strictly refused until those dependencies are proved.

## Per-key memoized extension storage

The original core reader's `current`/theme maps use a two-statement reader:
`@sites ||= {}; @sites[provider.current_site] ||= {}`. Extension storage
inference now recognizes exactly that empty-seed/index-empty-seed shape and
routes actual writes through the reader back to the nested owner ivar. The
source index contributes its type only; no database/site identity is frozen.
Nested `reader[key][other_key] = value` writes preserve each index type. Unknown
index/value writers remain unknown debt, including beside concrete writers.
Arbitrary readers, different ivars/receivers and nonmemoized copies do not gain
this alias contract. Empty indexed `||=` literals retain the receiver Hash's
value-type contract, just as empty ivar seeds already did.

Executable extension controls change sites at runtime, retain separate cached
values and parent/child storage, and count each real site-key evaluation once.
Original/SAME lowered CRuby/native match. Actual original reapplication derives
the nested container shape but still retains unresolved multisite/provider,
YAML metadata and runtime setting values. A known container shape does not close
a getter whose elements or key/provider contracts remain unresolved.
