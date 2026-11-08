# Recovery24: supported JSON acceptance and genuine frontend prerequisite

## Accepted scope

The supported anonymous core/no-plugins JSON request is accepted by the strict
compile-and-run command, not merely by compilation:

```sh
source harness/env.sh
RUST_MIN_STACK=33554432 CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4 \
  taskset -c 0-3 python3 fidelity/tools/probe_latest_json_request.py --cors-configuration enabled
```

Committed proof: `build/probe-portable-security-20261107-150855/evidence.json`.
It compares 25 complete original Rails / same-lowered CRuby / native responses,
126 request negatives, four cache-lifecycle controls and 18 other executor
controls. All 171 owned cache command fixtures cleaned up. Native trace is one
ELF, two readonly PG connections and one owned loopback cache connection.

JSON acceptance does **not** accept full query/options, a generic executor,
optional middleware profiles, plugins, HTML, preloads or browser rendering.

## Genuine frontend build

The original frontend is Rolldown-based, not the historical Ember CLI layout.
An isolated archive of original revision
`96ce8d44401a8a568ecc71561c26dca8ec6bfeb8` was materialized under
`build/recovery24-frontend/source`. Existing locked dependencies were copied,
not linked to the immutable checkout's writable dependency directories. The
actual production command compiled the original core entrypoint and manifest:

```sh
# Run only in an OWNED archive under fidelity/build, never the reference checkout.
# Copy root and frontend workspace node_modules as isolated copies first.
LEFTHOOK=0 EMBER_ENV=production NODE_ENV=production \
  RAYON_NUM_THREADS=4 UV_THREADPOOL_SIZE=4 \
  taskset -c 0-3 pnpm --dir fidelity/build/recovery24-frontend/source/frontend/discourse build
```

PNPM's initial automatic install ran original postinstall/type generation hooks.
It also generated an unrelated empty Fidelity hook config, which was archived
and removed. Use `LEFTHOOK=0` for further isolated builds; do not run build hooks
against the immutable checkout. The actual manifest SHA256 is
`353d6bcfe09088e3e998274f76ef246b174bb989709ad327f260a976064b4b1e`.

All **27,435 tracked original source blobs** match the pin after the build,
including raw symlink target bytes. Source audit:
`build/recovery24-frontend/source-audit.json`. Generated assets are actual build
outputs, not captured responses, dummy scripts or hand-written page content.

## Original HTML probe and boundaries

```sh
source harness/env.sh
CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4 taskset -c 0-3 \
  python3 fidelity/tools/probe_original_latest_html.py \
    --source-root fidelity/build/recovery24-frontend/source
```

This is an **original-reference prerequisite only**, not Stage5/native/page
acceptance. It audits every original source file before and after, uses a fresh
owned Valkey fixture, retains PG readonly/write rejection and the actual private
Vips version-call ownership checks, records raw HTML and real preload/script
observations, and always cleans up owned children. A relocated original worker
is allowed only under an owned build root and with the same bytes as both the
original checkout and the pinned hash attestation. Unknown roots, changed bytes,
symlink escapes, unowned PIDs/sockets and non-version operations remain rejected.

The first new probe omitted the standard Vips hash attestation and failed closed.
That harness defect was reviewed and corrected; no operation was rerouted to an
unowned helper or external service. The actual relocated worker's start, version
call and exit are retained in the subsequent probe evidence.

The normal HTML request then reached the real CSS compiler but failed when
`StylesheetCache.add` attempted an INSERT. No write reached PostgreSQL. Evidence:
`build/probe-original-latest-html-20261107-152928/`.

A distinct, stronger no-write profile was then tested from a **cold** CSS asset
cache:

```sh
# Actual Rails API, not a replacement application method or relaxed SQL guard.
CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4 taskset -c 0-3 \
  python3 fidelity/tools/probe_original_latest_html.py \
    --source-root fidelity/build/recovery24-frontend/source --prevent-ar-writes
```

`ActiveRecord::Base.while_preventing_writes` raises Rails' own `ReadOnlyError`
before dispatch. Original `StylesheetCache.add` already rescues it, so genuine
CSS assets compile to owned files without database cache writes. That does not
fix the next **uncaught, applicable** original operation:

```
Wizard#requires_completion?
  -> SiteSetting.bypass_wizard_check = true
  -> SiteSettings::DbProvider#save
  -> INSERT INTO site_settings (... bypass_wizard_check ...)
```

This occurs in `SiteSerializer#include_wizard_required?` while evaluating real
`ApplicationLayoutPreloader#preloaded_data` in `layouts/application.html.erb`.
It is not a compiler defect, frontend manifest error or optional middleware
count. The current real data takes this branch. No setting was forced off, no
setter/callback was replaced, and no cache or serializer output was fabricated.

Evidence: `build/probe-original-latest-html-20261107-153229/`. Strict result is
nonzero, original HTML500, no native HTML/browser/page acceptance. All original
source files remain unchanged, owned Valkey/Vips children exited, PG guards
remained intact. Existing private-PG permission was consumed; this work does not
reuse it or infer new write authority. A new permission decision is required
before executing that settings write in a new isolated original HTML fixture.

## Checks

- `test/oracle_isolation_test.rb`: 18 runs, 133 assertions, no failures.
- `test/test_original_latest_html.py`: source mutation, missing source,
  non-blob and raw-symlink-byte controls pass.
- Baseline `make -C fidelity verify`: passes after guard changes,
  `build/verify-20261107-153643/` (use the RUST/CARGO environment above).
- Existing native JSON proof, compiler/runtime tests and immutable reference
  checkouts are preserved. No shared writes, private-PG reuse, services,
  deployment, public push/PR or helper-agent work occurred.
