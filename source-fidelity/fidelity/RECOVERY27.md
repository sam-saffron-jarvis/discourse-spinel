# Recovery27 — real file-backed URL resolution and concrete layout composition

SAME019/session/source trees. Consumed private-PG approval, failed original HTML
invocation and cleanup records are untouched. No Rails boot/HTML retry, PG/cache
effect, approval prompt, helper lane, or deployment/publication is involved.
Supported native JSON150855 remains accepted for its previous scope. All original
HTML200/native HTML/browser/page/full019 acceptance remains false.

## URL checkpoint

`make verify-asset-urls` executes original `ApplicationHelper#script_asset_path`,
`asset_cdn_path` and `is_brotli_req?` in a minimal supplied unit configuration,
using **actual Propshaft::LoadPath/Asset/Resolver::Dynamic** plus real ActionView
asset_path on the reference side. This is not the old supplied URL map.

The native/shared counterpart is typed shared framework code at
`roundhouse/runtime/ruby/action_view/source_asset_paths.{rb,rbs}`, automatically
exported by the action_view subtree and explicitly required by action_view.rb.
It performs real directory discovery and cached lookup, original root precedence,
original pre-digested detection and source-content SHA1+version naming, then
Rails root/fixed-host handling and the source-derived Discourse S3/CDN rewrite.

The exact pinned Discourse initializer keeps ONLY SourceMappingUrls. That compiler
inherits the original empty-Set referenced_by; URL hashes therefore do not omit
applicable reference contents. No content compiler, server, watcher, integrity or
full request lifecycle is claimed. Fixed HTTP(S)/protocol-relative host/no-option
asset_path is explicit; callable/sharded hosts refuse rather than being invented.
Pathname-to-String and typed iteration/replacement adaptations are recorded.

`generate_asset_urls.rb` verifies both cached gem packages against Gemfile.lock
checksums, verifies signatures/payload, and compares all installed Ruby members
against package bytes. Selected original app/framework spans/hashes and native
runtime/signature hashes are recorded in portable_asset_urls.json. Original
checkout and installed gems remain unmodified.

Green proof: **build/asset-urls-5p1ivqk6/evidence.json**.

- Thirteen original/shared/native records match: genuine rolled entrypoints and
  browser scripts, changed roots/hosts/S3/CDN/brotli/missing encodings, fallback
  CDN values, query/fragment tails, source version changes and pre-digested names.
- Real files are read/hashed. Explicit unit fixture names with spaces/quotes/
  Unicode reuse genuine source bytes, not production claims or a new frontend.
  Nested root deduplication and competing root order preserve actual Propshaft.
- Missing files are refused, not turned into plausible /assets/name URLs.
- Four native mutants compile and fail for wrong digest, omitted root, wrong
  brotli path and wrong file-root precedence. Trace: one execve/zero connects.
- Framework owner test1/7 and strict typed-runtime invariant pass. Initial test
  loader dependency failures and the initial typing failure are preserved. Typed
  equivalents retain dotfile traversal and lazy digest behavior; no source behavior
  or acceptance control was removed to get green.

## Concrete asset layout fragment

`generate_application_asset_fragment.rb` selects the exact contiguous original
layout span containing browser-update preload, browser-detect script and module
preloads (including the supplied unit staff branch). Reference compilation uses
actual `ActionView::Template::Handlers::ERB::Erubi` HTML options escape:false,
trim:true and real OutputBuffer. In ActionView, escape:false means append=,
which escapes ordinary String values but retains SafeBuffer output. The native
lowering preserves literal source bytes and executes each original Ruby expression
once, escaping String expressions and accepting only typed trusted fragments.

First proof: build/application-asset-fragment-9504udu2/evidence.json. Four supplied
unit root/CDN/role/cacheability contexts match exact normalized output, real nonce
and CSP agreement, original resource-preload effects and body identity. Native
explicitly reads/hashes39genuine graph assets, also actually digests browser source
files; later rendered-URL delivery below covers55distinct asset URLs.
Missing URL fails before nonce/resource effects. Native one execve/zero connects.
Four native mutants reject unescaped URL strings, escaped trusted helper HTML,
omitted modules and lost result type. Unit staff values are NOT an authorization
matrix and the fragment is NOT a request/page or static replacement layout.

## Concrete data-preloaded JSON script composition

The same native execution now also renders the exact original
`<discourse-assets-json>` span through actual ActionView ERB vs typed composition,
then passes both selected body parts through the original nonce injector.
`raw(preloaded_json)` retains the source's String-to-trusted boundary; escaping
JSON as HTML is explicitly rejected. Exact preloaded_json/escape_unicode methods
acquire the supplied unit preloader once; nil, synthetic serialized strings,
closing-script/U+2028 text and invalid UTF8 are exercised without creating fake
Site/settings preload values. The reference explicitly loads/checks the JSON gem
encoder in its minimal ActionView context; no full Rails/AS/Oj behavior is inferred.

Proof: build/application-asset-fragment-73wak115/evidence.json. Seven native mutants
fail the actual assertions, including HTML-escaped raw JSON, unsafe script closers
and double preloader acquisition. Acquisition/type, nonce agreement, source trust,
resource effects and missing-file-before-effects checks remain intact. Source spans,
raw helper span, hashes and exact native lowering are recorded. Initial reference
encoder check ran before JSON was required; that dependency-order failure is
preserved and fixed without changing original/helper behavior.

## Concrete import-map script on the same source path

The cumulative native program now also renders the exact import-map `<script>`
span of `layouts/_plugin_js.html.erb`, using the original `generate_import_map`
helper, live genuine manifest imports, actual URL resolver and exact source
optional/required plugin-stub methods. Original ActionView ERB and same shared
CRuby/native match. Core unit vectors are empty; changed plugin/theme vectors
are explicitly supplied unit inputs, NOT plugin activation/permissions or fake
production metadata. Outer Discourse.find_plugin_js_assets and the rest of the
partial are not represented as executed.

Proof: build/application-asset-fragment-4wnth026/evidence.json. Three source spans
(import-map, browser assets, data-preloaded) flow through the same real nonce/CSP
substitution while retaining raw JSON/trusted HTML and ordinary String escaping.
53 real import bindings are resolved; the script-graph set explicitly pre-read/
hashed here is39files/10,637,925bytes (not53distinct reads). Ten compiled native mutants
fail for wrong URL escaping, trusted-result type, modules, raw JSON, script closer,
repeated acquisition, stable import keys, escaped import JSON and optional-stub
behavior. Missing import-map files preserve the original distinct ordering: nonce
acquisition occurs before URL failure; resource links remain unmodified.

Missing-file behavior now retains exact Propshaft::MissingAssetError type and
message, not a generic candidate ArgumentError. URI detection also retains the
actual Rails regex. The shared framework source/signature and original error
method spans are recorded. URL/type proof: build/asset-urls-l336ro68/evidence.json.

## Verification so far and next read-only asset boundary

Cumulative URL/composition run: build/recovery27/final-composition.log,
asset-urls-ifu4x21z and application-asset-fragment-s1t4zhpp. Typed runtime PASS;
resolver owner1/8 PASS. Rebuilt cumulative readonly AR baseline
**build/verify-20261107-203927** PASS. No earlier standalone leaf/JSON campaign
was rerun. Full declaration gate remains unaccepted.

## Actual read-only JS asset responses (no listener)

After concrete layout composition, the next necessary asset-delivery component
was executed rather than stopping at URL generation: actual Propshaft::Server,
original SourceMappingUrls plus the pinned Discourse compiler prepend, vs the
shared typed `SourceAssetResponse` and same lowered CRuby/native code.

Proof: build/asset-response-jdsm8e2w/evidence.json. Ten isolated Rack method calls
match status, exact header case/values, actual body bytes/hashes, GET/HEAD behavior,
stale/missing 404s, fallback effects and URI decoding. Invalid percent escapes
refuse. Native watcher/nonidentity-source-map/unsupported-MIME profiles explicitly
refuse, never silently skip applicable processing. Four compiled native mutants
reject HEAD body leaks, stale digest admission, wrong cache headers and omitted
decoding. One execve/zero connects; **no listener, service or original Rails boot**.

The target actually locks Rack2.2.24 (not an installed Rack3 copy). Initial header-
version/dependency assumptions failed and remain in history; the reference loads
its genuine Rack dependency and the native component retains Rack2 header names.
Cached Rack package bytes are now verified too. No reference version was forced.
The generic URI decode method already exists in the stdlib/native package; its
String return contract is recorded in the shared analyzer and exercised natively.
Shared owner1/8 and strict all-runtime body typing pass.

This JS-only, source-mapping-only, no-watcher component is not the full asset
server, CSS compiler, HTML middleware stack, page/controller or browser result.
The full real-data layout still requires ApplicationLayoutPreloader/Site/settings/
theme acquisition and the already-known stylesheet/wizard effects; captured unit
values must never substitute for them. All full HTML/page acceptance stays false.

## Rendered-URL delivery and the next actual cache lifecycle

The same native program now consumes URLs extracted from the real source
fragments/import map through the actual read-only asset component. Proof:
**build/application-asset-fragment-4muzided/evidence.json**. All **55 distinct
rendered asset URLs / 13,813,751 response bytes** match original/shared/native,
not just their URL text. These include real rolled modules and the original
browser scripts. This is still selected spans + supplied unit data/roles, not
an actual HTML endpoint or browser acceptance. The explicit script-graph pre-read
set is39files/10,637,925bytes; earlier notes saying53pre-read files were inaccurate.
55actual deliveries are separately recorded and must not be confused with53
manifest import bindings or with a complete page.

This exposed `MRB_REGEXP_STEP_LIMIT` on a genuine long worker filename. The first
two failures and bounded instrumentation are retained in build/recovery27/.
Diagnosis localized it before compiled-content acquisition to the upstream digest
extraction regex. A canonical `.digested.js` suffix provably cannot match that
regex's negative-lookahead path; a source-equivalent suffix fast path now avoids
its exponential backtracking. Global regex safety limits were NOT raised. The
compiler's no-directive literal precheck is also source-equivalent, not an omitted
compiler. Long-name regression is in the shared owner suite and genuine delivery.

Next, actual Propshaft **NullFileWatcher** cache lifecycle was executed (not a
fabricated no-op or a claimed ActiveSupport/evented watcher). Source callback
clear+seed runs under a real mutex every call. Native requires the explicit `null`
profile; unknown/AS watcher profiles still refuse. An owned unit file is changed
between genuine-byte versions then deleted: stale digests invalidate, new bytes
reseed, and deletion404 matches original. With sweeping disabled, the original
cached-body behavior is retained. Only the labelled unit fixture is mutated;
shared/source files, PG and external caches are untouched. Proof:
**build/asset-response-e0co154y/evidence.json**. Shared owner suite now1test/12assertions
and the strict all-runtime typing invariant pass. No watcher thread, listener,
persistent service or new permission was used.

## Current real-data boundary (not a new HTML experiment)

A bounded SELECT-only diagnostic on shared PG5499, with server readonly ON,
confirmed the current cold-site branch conditions: wizard_enabled=true,
bypass_wizard_check=false, login_required=false, and more than the original
Wizard initializer's15undeleted topics. Evidence:
`build/recovery27/readonly-real-preload-boundary.json`. These diagnostic values
are NOT fed into helpers or frozen into candidate settings.

Pinned `ApplicationLayoutPreloader#preload_anonymous_data` calls Site.json_for;
on a cold owned cache, SiteSerializer evaluates the original Wizard branch and
requires `SiteSetting.bypass_wizard_check = true`. The original stylesheet-cache
INSERT and this setting INSERT remain genuine effects, not optional callbacks.
No Ruby request/callback/HTML retry or write was attempted to collect this
SELECT-only diagnostic. Current permission remains consumed. Full real-data HTML
cannot be established by promoting unit preload/theme/plugin vectors into live
state or reusing prior private data. Independently permitted source work is not
permanently latched off; only the actual prohibited experiment/write branch stays
blocked. No new permission prompt or duplicate notification was sent.

## Final committed-code verification

- Real URL parity: `build/asset-urls-cqz2ftyz/evidence.json` (4native mutants).
- Three concrete source spans plus actual55URL deliveries:
  `build/application-asset-fragment-jp6gkapk/evidence.json` (10native mutants).
- GET/HEAD/file/cache lifecycle: `build/asset-response-4pbo4rzp/evidence.json`
  (5native mutants, explicit NullFileWatcher and owned-file mutation checks).
- Shared owner1/12 and strict all-runtime typing PASS; logs under
  `build/recovery27/response-owner-extended.log` and `null-watcher-typed.log`.
- Final cumulative readonly baseline **build/verify-20261107-214227**, PASS,
  release build and fresh emitted native execution on clean implementation commits.
- Original27,435source blobs unchanged, consumed authorization/one failed Rails
  invocation/cleanup unchanged. Task+retained cancelled trees~106.4GiB/150cap;
  quota39% at21:47 Nov7, deadline unchanged. No publication/services/permission ask.

The concrete renderer still contains ONLY the recorded selected spans. Full
original layout control flow, ExtraLocales/client bootstrap, real Theme/Site/
settings/preloader acquisition, complete HTML controller/ingress/middleware and
browser execution remain unaccepted. Native JSON150855 stays accepted. The real
cold Site/Wizard mutation path is specifically prohibited; it must not be replaced
with unit values, a warm saved cache, omitted callbacks or renewed private-copy
permission. Other permitted source work is not globally or permanently stopped.
