# Patched core-only shared SiteSetting candidate

This directory is the **authorized changed application source** profile, not an
immutable-source proof. The original checkout and `source/discourse` copies stay
unchanged. `MANIFEST.json` records the pinned baseline, input hashes, complete
candidate file hashes, reproducible generation and explicit unintegrated scope.
Historical source-only gates are not changed by this work.

## Current implementation boundary

- `portable_read_store.rb`: shared application read-cache with source wire-type
  coercions, defaults → DB → global precedence, locale defaults, mandatory list
  values, per-site snapshots/invalidation, atomic failed-refresh behaviour,
  synchronized cache access and a post-publication refresh callback.
- `portable_global_configuration.rb`: live defaults/configuration/environment
  resolution preserving the original file-provider versus env-provider choice
  and `BaseProvider#resolve`'s false/blank/coercion semantics. Unsupported ERB
  configuration explicitly refuses; no effective configuration is snapshotted.
- `portable_pg_provider.rb`: real read-only PG query/provider, explicit site-to-
  connection registry, and readonly-session checks. It never opens another site's
  connection by guessing its name and has no DB mutation implementation.
- `portable_core_definitions.rb` and `portable_core_readers.rb`: generated from
  **all 1,110 pinned core YAML declarations**, plus the original default-locale
  API fallback (1,111 definitions). Generation is build-time Ruby/YAML parsing,
  not runtime `define_singleton_method`, captured values, or observed types.
  Read-store special cases refuse until their actual source contracts are wired.

Regenerate using `ruby fidelity/tools/generate_portable_settings.rb` from the
workspace root. Generated accessors use the facade's `portable_store` and
`portable_site`. The **hybrid Rails integration** below now exercises that
boundary in a genuine isolated Rails checkout. It is not yet a complete native
SiteSetting bootstrap.
These modules are not a reduced test-only SiteSetting or a replacement topic
backend. The provider uses the original settings-table read query, not new topic
SQL. New code is shared between CRuby and native Spinel.

## Executed proof, not page acceptance

`tools/probe_portable_settings.py` runs the existing guarded, zero-plugin original
Rails/query reference FIRST, then compares the new read-store with the original
SiteSetting in that process. Separate CRuby and native processes execute the same
candidate code and independently read the live readonly DB and configuration.
Only the existing PG primitive driver adapter differs between the pg gem and
spinel-pg, as in the previously established database runtime.

Initial live proof compared **754 non-secret, non-hidden scalar settings**,
including three actual DB modifications. Values **and Ruby classes** match.
The consumer changes its own process environment, verifies cached versus
refreshed configuration and post-publication callback order, then restores it.
No shared settings rows are changed. Wrong endpoint controls on both runtimes
fail before any `connect` syscall; a deliberately corrupted value fails parity.
The existing owned Valkey/helper oracle fixtures attest cleanup.

Use native `--no-inline-hot --cc=clang --jobs=4` for this candidate. The default
forced-inline build generated a `setjmp`-using getter that GCC refuses to force
inline. No compiler workaround or weakened application result was adopted; the
documented non-forced-inline profile runs the same source. Schema generation is
batched to avoid one large native constructor stack frame.

The expanded live proof now invokes **755** actual accessors from the SAME
production `PortableScalarReaders` module on CRuby and native (default-locale's
fallback comes from the core reader module). One additional required query enum,
`RemoveMutedTagsFromLatestSiteSetting`, is admitted as raw only after checking its
complete pinned class/parent/declarations and lack of wrapper activation. Other
enums, especially the genuinely wrapping duplicate-title enum, still refuse.
The invocation list is generated from declarations, never from captured values;
this avoids extending Spinel's deliberately unsupported runtime-name public_send
without replacing any production getter. Native tracing verifies one ELF exec
and direct readonly PG connections only, with no Ruby child/oracle data input.

A separate same-source scalar-module unit exercises non-theme scoped arguments,
real enum defaults/DB precedence, readonly refusal and both reversible group-map
branches. Its Group enum constant is copied byte-for-byte from pinned source and
manifested as UNIT-only; the flag is an explicit controlled unit input, NOT a
fake production UpcomingChanges/permission implementation. No fixture is imported
by the live/native application entrypoint.

Additional same-source unit controls cover false/zero/empty/NULL, all supported
wire coercions, locale and global precedence, two-site cache isolation, removed
DB overrides, refresh/invalidation, failed refresh atomicity, callback order,
unknown settings, explicit write/security-map refusals, configuration provider
choice and unsupported ERB. They use labelled memory/config fixtures only; those
fixtures are never production/native data inputs.

## Hybrid Rails application integration

The complete candidate `app/models/site_setting.rb` changes only extension
wiring; all original helpers, validations and callbacks remain. A generated
`PortableScalarReaders` module replaces runtime name synthesis for supported
scalar declarations. `PortableRailsExtension` refreshes the shared cache before
original special-setting refresh (which needs the current promotion controls),
then calls original cache invalidation after both complete. It uses the real
application provider/current-site routing, not a guessed database or an effective
settings export. Original theme/upload/object/enum/upcoming/group-map/client and
change-bus implementations remain responsible for their real contracts.
Default-locale's special API and deprecated wrappers remain original too.

This is explicitly a **transitional hybrid**, not full cache replacement:
publication of each shared store snapshot is atomic, but atomicity across the
original special-setting cache and shared scalar cache is not claimed. Writes
through the extension are refused; persistence/admin coverage is not accepted.

`tools/probe_portable_rails.py` compares original Rails FIRST with a separate
pinned local clone plus the manifest's candidate files. It verifies **3,417**
getter/predicate/scope/map/client records, original query constructor matrix and
actual anonymous security composition, actual `/latest.json` HTTP200 and its complete parsed payload. The native
full query/page is still unproved. Both document requests currently return the
same real frontend-build HTTP503, NOT a page pass. Initial clone HTTP500 was a
missing real server-side JS processor cache, not a setting difference; the runner
now copies and hashes the real existing content-addressed server-side bundles.
The unchanged application recomputes their source digests. No frontend manifest
is invented.

The sandbox verifier files are copied **byte-for-byte** into the same relative
layout next to the isolated clone. Thus the existing exact Vips source path,
hash, child ownership and endpoint checks remain intact without a new helper
permission. Historical oracle profiles still require the original root; only
this separate profile overrides the expected application location, retaining
complete unchanged-file hash and cleanup checks.

## Native shared context + unpruned security expression

`PortableSettingsContext` is a source-defined bootstrap adapter, wired into the
candidate model alongside the Rails adapter. It accepts an actual provider/site,
builds and refreshes a replacement before publishing it, and captures no values
or endpoint. Rails retains its real current-site routing overrides. The native
probe uses the same context/accessors and real readonly connection registry.

`tools/probe_portable_security.py` now executes the ORIGINAL category-security
expression **without** the historical anonymous construction specialization:
`SiteSetting.suppress_secured_categories_from_admin` remains in the compiled
Guardian method. It compares original Rails FIRST with same-lowered CRuby and
native, including a fresh settings bootstrap/reference cold getter, five live
rows, seven SELECT-only fixture rows, NULL/dangling/preload/cache/type controls
and a wrong-filter negative. Native traces prove one ELF exec/two direct PG
connections; wrong endpoint controls must reject before connect. Original owned
reference fixtures are cleaned. This is still ANONYMOUS EXPRESSION scope only,
NOT native admin/member coverage, complete default_results/list_latest or a page.

The two fixed mixins are read from the full candidate model and installed in
explicit-receiver form after the lowered model declaration and before bootstrap;
that transformation is manifested, not described as unchanged original boot.
Native special getters/Rails metadata/change-bus integration remain unproved.
Initial native refusals exposed missing bootstrap dependencies: stdlib JSON loads
Date, activating the existing SQL Date quote branch; the probe now loads the
actual existing date formatter, Rails runtime and Base64 dependency. No fake
formatter/application method or compiler emulation was introduced. The additional
runtime source is hashed before/after; common modules remain identical across
CRuby/native.

## Growing the actual latest algorithm

`tools/project_core_latest.rb`/`probe_portable_latest.py` measure a conservative
whole-method closure rooted at the real initialize/list_latest/latest_results/
default_results/create_list methods. All 20 selected methods retain exact source
bytes, including their unexecuted option branches, constants, accessors, callback
registry initialization and visibility. Selection closes over same-owner names
in complete method bodies, not an observed settings value or live-only trace.
Original guarded core reference runs first. Initial strict inventory175743 has
31 missing-core-constant diagnostics (supporting models, registry, filters and
poster/list helpers); no output is executed or accepted. This is a dependency
measurement toward latest, not full default_results or a rewritten topic backend.

The growing helper profile also includes complete pinned list/poster/user/group
lookup sources, the real verified ActiveModel serialization concern (not an
empty module), and readonly model projections with an actual 334-column/14-table
PG catalog schema. The original fixed PostActionType forwarding macro blocked
source-method selection; the candidate now expands its exact names/rest-argument
calls into explicit shared methods. Real original/patched Rails comparison185214/
185218 passed **3,435** setting/client/flag-metadata/arity/parameter records and the full latest
JSON payload. The candidate model projection has a SEPARATE mutation-rejecting
source audit; it is never admitted as byte-identical original source.

Current optional settings caller signatures use a conservative primitive union,
not a type guessed from YAML defaults or the current site: live global overrides
can change a getter's primitive class. These signatures supply no implementation
or values; the real native module remains mandatory. A User-or-nil field contract
is also an explicitly experimental compile-only input: the184300 measurement
showed it does NOT resolve the remaining nil-caller inference errors. No native
identity capability or lowered execution is inferred from those annotations.
Latest method output still REFUSES missing real cache/config/registry/filter/search/
tagging/flag/DB helpers plus nil caller types. Never execute this failed output.

## Still unproved / next integration

This is **not full SiteSetting compatibility, native TopicQuery or /latest/page
acceptance**. Do not replace those claims with getter parity. Next is the same
native accessors/settings path in actual query/security, followed by required
special-setting contracts and the full serialization/document path. In particular:

- enum wrappers, uploads/object hydration and theme overrides;
- upcoming changes, group-specific enabling and group security-map semantics;
- original change-bus/client/cache invalidation integration and client payloads;
- validation/setters/persistence/admin APIs and plugin activation;
- full patched core query/security → serializer/controller/document/browser.

Writes and plugins can remain explicitly unsupported for the first milestone,
but required core/security behaviour cannot be silently disabled. No fake
permissions, frozen production values, canned SQL/JSON or frontend manifest are
authorized shortcuts. DB writes need new isolated-fixture authority; none is
implied by this source change.
