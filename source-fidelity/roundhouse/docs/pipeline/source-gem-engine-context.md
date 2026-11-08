# Source-gem engine ownership before inference

A source gem can register different features defining the same constant under
mutually exclusive engine predicates. Treating both as unconditional declarations
poisons constructor and method lookup with a fictitious reopen. The measured core
MiniSql provider hit exactly this: original `RUBY_ENGINE == 'jruby'` selects the
JDBC or PostgreSQL definition of `MiniSql::Postgres::Connection`.

`ingest_app_for_target` can select source dependencies for Spinel only when a
predicate agrees on BOTH CRuby (`ruby`) and native Spinel (`spinel`). A predicate
such as `RUBY_ENGINE == 'ruby'` disagrees and does not select either inventory.
Unknown predicates also retain both. The source consumer APIs and other targets
remain unspecialized. No original file or source expression is edited.

The bounded world checks refuse engine assignments/shadows, constant mutation,
core lookup overrides/refinements, symlink/unknown source worlds and opaque app
lib/model file-root effects that would otherwise be unretained. Explicit app or
cross-gem requires of an alternative prevent excluding it. These are conservative
proofs, not an arbitrary filename/platform allowlist. Native finite-program world
guards still reject dynamic loads, eval, callbacks or namespace effects outside
that loader's profile; source selection is not permission to omit such effects.

A selected inventory is marked on App and cannot be emitted through another
target's loader. It uses the shared finite file-program IR even without autoloads:
known agreeing resource branches become their original ordered program steps;
loads, declaration events, global writes and feature identities remain where they
ran. Reusing the native eager declaration aggregator would erase file effects and
is deliberately not the implementation. Emission rechecks late engine writes and
core-owner changes. The generated Spinel Ruby is also executed unchanged by CRuby.

The reduced control proves inherited constructor/keyword ABI, actual source
feature order and effects against original, SAME lowered CRuby and native, with
negative engine/lookup/explicit-load/computed-mutation and incompatible-target
worlds. It is NOT a complete MiniSql, RailsMultisite, PG codec or core settings
implementation. Original core input remains strictly refused, now at the real
RailsMultisite namespace feature contexts and other genuine dependencies, rather
than a fictitious simultaneous PG/JDBC parent definition.
