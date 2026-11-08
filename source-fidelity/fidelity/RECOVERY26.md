# Recovery26 — write-free native HTML helper dependencies

The consumed Nov7 private-PG authorization and failed reference remain untouched.
No Rails application boot, original HTML retry, PG/cache effect or permission
prompt is part of these checks. Supported native JSON150855 stays accepted for its
existing scope. Original HTML200/native HTML/browser/page/full019 remain false.

## Checkpoint 1: asset preload helpers

`tools/generate_asset_preloads.rb` records original source/hash/spans for
`ApplicationHelper#preload_script`, `preload_script_url`, `module_preloads_for`
and `add_resource_preload_list`. The original oracle executes the exact methods
in a minimal isolated method context, not a running Rails controller. Explicit
unit inputs supply graph, URL mapping, nonce and isolated controller state.
URLs and nonce strings are **not production settings/nonces or saved oracle data**.

Candidate transformations make the asset graph and resource collector explicit,
replace the string-only generated attrs presence predicate, and retain trusted
result type using shared typed `ActionView::HtmlFragment`. This small wrapper is
not a String subclass/full SafeBuffer emulation; conversion to String drops the
trust boundary. The original returns SafeBuffer, while the candidate must return
the explicit trusted wrapper; a plain String cannot pass the type check. The
original's raw URL/entrypoint/nonce trust boundary is unchanged, not upgraded to
untrusted URL handling. SafeBuffer attribute input is outside this typed profile.

Proof: `build/asset-preloads-4gj635ao/evidence.json`.

- Full output bytes and ordered resource-list effects match original/shared/native.
- Attr keys/values include ampersand, quotes, angle brackets, newline and Unicode;
  module/defer, absent/empty attrs, dynamic nonce/URL inputs and entrypoint fallback
  are exercised. Original fallback is explicitly a unit URL, not an invented asset.
- Module preloads retain order and deduplicate, ignore nil/unknown entries;
  resource links retain duplicates and are lazily allocated on the supplied
  controller, with cross-controller isolation. Missing asset URL fails before effects.
- The existing genuine graph is used, not re-proven/reimplemented. Native reads
  the genuine referenced built files, and trace has one execve/zero connects.
- Shared safe-fragment owner tests: 2 tests/6 assertions pass. Shared runtime
  `every_runtime_method_body_is_fully_typed` passes. Native helper actually runs.

## Checkpoint 2: genuine nonce generation and CSP substitution

`make verify-csp-nonce` executes pinned `ApplicationHelper#csp_nonce_placeholder`,
`ContentSecurityPolicy.nonce_placeholder` and the complete original nonce injector.
The exact anonymous-cache key is a declaration only, not a replacement cache.
The candidate reuses the existing source-backed fast_blank header adapter.

Proof: `build/csp-nonce-pj2f2544/evidence.json`. Five supplied unit contexts match:
nil env, cacheable env, uncached env, preexisting env nonce and preexisting header.
Actual SecureRandom produces fresh placeholder hex/nonces; format, uniqueness,
memoization, agreement between both script bodies and both enforced/report-only
CSP strings are checked **before** normalizing only random bytes for comparison.
Native getrandom calls are traced. Existing supplied values are explicit unit
inputs, never captured production nonce/settings.

The test integrates the actual preload-script helper, trusted result type and
resource-list effects. It retains first-script-src substitution, marker removal,
no-marker passthrough, original response-array identity vs rewritten array,
ASCII/NUL header blank behavior and cross-env generation. An ordinary String
cannot pass the trusted-result predicate. Native trace: one execve, zero connects.
No policy builder, Rails request, anonymous cache, PG, original HTML200 or browser
acceptance is inferred from this dependency result.

## Checkpoint 3: exact layout preload JSON string helpers

`make verify-layout-preload-json` executes exact unmodified `escape_unicode` and
`preloaded_json` method spans under an explicitly **standalone JSON** unit context.
The supplied preloader contains unit serialized strings/nil, not saved real
Site/settings/preload data. No Rails/ActiveSupport/Oj encoder boot or full
ApplicationLayoutPreloader behavior is claimed.

Proof: `build/layout-preload-json-enccr28v/evidence.json` (prior green8vfzzeyy).
Seven cases match source-context CRuby, shared CRuby and native: script-closing
sequences, U+2028, original U+2029 behavior, quotes/backslashes/Unicode, nil, empty,
and invalid UTF-8 scrubbing. Nil preloader, output String type, retained nested
serialized-string type, exact acquisition count, repeated acquisition and input
immutability are asserted. Raw script closers/U+2028 cannot leak. Native one
execve/zero connects. First test failed because its invalid-UTF8 *unit literal*
was frozen; using a duplicate before force_encoding fixed only the test input.
The failure log remains. No original/helper behavior was weakened.

## Final cumulative verification and executable negatives

`build/recovery26/final-helper-tests.log` records all three green checkpoints:

- `build/asset-preloads-onf34dk4/evidence.json`
- `build/csp-nonce-6mi575n4/evidence.json`
- `build/layout-preload-json-enccr28v/evidence.json`

Five intentionally incorrect native programs compile and then fail the real
unit assertions: unescaped attrs, wrong nonce, reversed resource order, wrong CSP
nonce and reused constant nonce. This prevents normalization/trusted wrappers
from hiding incorrect output. Original/shared/native also reject a genuine
manifest with absent asset files before output. Plain String trust is refused.
An owning shared-runtime native/CRuby matrix checks fragment input/output copy
isolation, trust type and idempotence; ordinary framework owner tests pass2/6.
The action_view subtree is already automatically exported with its signatures by
`project.rs::spinel_files`; `action_view.rb` requires the new fragment explicitly.
The shared typed-runtime invariant passes.

Final cumulative readonly baseline: **build/verify-20261107-192313**, PASS (includes
release compiler build and fresh emitted native execution). No graph-only or old
JSON acceptance campaign was rerun; the supported JSON150855 proof remains intact.

## Exact remaining boundary

The next permitted source path is genuine Propshaft/CDN URL acquisition/resolution
and typed layout/ERB consumer composition; full EmberAssets request/production
cache/build-error lifecycle and real ApplicationLayoutPreloader/Site/settings
assembly remain. Current URL values/policy strings and preloader are explicitly
unit collaborators, not a real controller/request, production nonce/config or
static replacement page. Complete HTML ingress/middleware, CSS/wizard effects
under explicit authority and browser execution are still unaccepted.

Only the original writable-reference branch is specifically blocked: the Nov7
approval is consumed after its failed single invocation. No private PG copy,
snapshot, restore, second Rails HTML experiment, native/compat PG write or
background permission prompt occurred. Write-free source work remains permitted;
no new global/project-wide stop or implied approval is created here.
