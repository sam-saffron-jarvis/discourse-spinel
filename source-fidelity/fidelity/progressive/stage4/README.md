# Full serializer checkpoint — not a controller request

Run from the workspace root:

```sh
source harness/env.sh
export CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4
taskset -c 0-3 python3 fidelity/tools/probe_serialized_latest.py
```

This command strictly emits, compiles **and executes** the native ELF, runs the
same lowered application Ruby on CRuby (only the existing PG-driver substitution),
and compares against genuine original, no-plugin Rails. It reruns Stage0–3b and
all their negative controls. A compile/runtime/parity refusal exits nonzero.

The new observation is the **complete TopicListSerializer output**, encoded via
the existing framework ActiveSupport JSON API. It includes all declared topic
fields, poster associations, side-loaded users, primary groups and flair groups,
NULLs, booleans and UTC millisecond timestamps. The immutable originals, verified
gem packages and original application declarations are the generation inputs;
observed settings, records and JSON are never candidate/runtime inputs.

The supplementary source manifests are linked by hash from `compat/MANIFEST.json`:

* `SERIALIZER_SOURCE_MANIFEST.json`: actual AMS0.8.4 root/uncached/side-load read
  algorithms; source-declared readonly class-attribute defaults.
* `SERIALIZER_DECLARATIONS_MANIFEST.json`: actual serializer inheritance,
  attributes, includes/aliases and fixed association declarations expanded to
  ordinary shared methods. Alias methods are not overwritten by default getters.
* `READ_DEPENDENCIES_MANIFEST.json`: whole guarded source methods, live theme
  modifier/schema/configuration reads, avatar/upload/color/URL dependencies and
  exact original emoji/font assets. URI byte encoding is differential-tested
  against the pinned Addressable implementation. Avatar fallback versioning
  hashes the real font and reads the actual Vips C library version without a
  subprocess; it does not use an observed version or generated-avatar snapshot.

Database hostnames follow the original **development database.yml host_names**
branch, not the unrelated GlobalSetting hostname. The probe executes the actual
source-declared application timezone through the framework runtime. Neither fix
captures an effective runtime hostname or timestamp.

Supported execution remains anonymous core latest, English locale, stored
nonnull slug/fancy title, ASCII usernames, no enabled localization/nesting/status,
no activated serializer caching or configured CDN. Unimplemented branches refuse;
no live feature setting is forced off. Nonempty tag/image/thumbnail/custom-field
values and authenticated/other routing profiles remain unproved. Fresh read
replacements do not claim original distributed-cache effects or query counts.

**No controller request acceptance:** this checkpoint has no native route/action,
request middleware, HTTP status/headers/paging-link proof or browser page. Those
flags stay false. Original-versus-shared full Rails `/latest.json` integration is
a separate regression command (`probe_portable_rails.py`), not native acceptance.

Generation is reproducible with the three `generate_*serializer*.rb` tools
(`generate_portable_serializers.rb`, `generate_serializer_declarations.rb`,
`generate_serializer_read_dependencies.rb`) followed by
`generate_portable_settings.rb`. Focused regression tests include source and
manifest tampering, historical projection isolation, failed-stage flags, live
hostname changes/refusals, URI escaping and actual native Unicode codepoint reads.
