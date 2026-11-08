# Recovery25 — one original Rails HTML reference attempt (failed)

The fresh human approval in `run/PRIVATE_PG_HTML_AUTHORIZATION_20261107.json`
was atomically claimed before snapshot/setup. Its SHA256 is
`45ef2a1be8bc05a4ebade3ebd7948218049df732bdabcee50bd4260120fc4ca7`.
The approval is **consumed**, with one actual Rails invocation. Neither this
harness nor a recoverable setup/guard error authorizes another experiment.

## Implemented isolation

- `tools/private_pg_fixture.py`: exclusive usage claim, readonly shared dump,
  independently owned postmaster/datadir/private Unix socket, private restoration,
  restricted Rails role and wizard-only row policy, before/after shared readonly
  fingerprints, process-identity checked cleanup of raw snapshot and all PG state.
- `tools/private_pg_oracle_guard.rb`: explicit opt-in policy requiring the exact
  live claimed runner and owned PG identity at construction and statement dispatch;
  original CSS-cache and wizard-setting callers only; other writes, endpoint
  overrides, extra roles, external effects and multistatements fail closed.
- `tools/private_pg_html.py` and `tools/private_html_reference_probe.rb`: one-use
  original Rails reference driver, unchanged built source, live isolation negatives,
  intended original HTML/JSON preload comparison, sanitized metadata and failure
  results. This is not a native HTML implementation or page acceptance target.
- Default `oracle_isolation.rb` policy remains readonly unless the private manifest
  is explicitly supplied. No new native/compat write authority was introduced.

## Actual run and preserved failure

`build/probe-private-original-html-20261107-182916/` contains sanitized evidence.
`run/PRIVATE_PG_HTML_RESULT_20261107.json` is the durable failed outcome.

Snapshot/setup and live guards passed. Eight recorded private backends matched
the owned postmaster. Original callbacks successfully inserted two CSS cache
rows. The parent 180-second limit then interrupted large common stylesheet SQL
handling. HTML500 was observed; the wizard path and intended preload comparisons
were not reached. **No original HTML200, native HTML or browser acceptance.**
The unapproved-private-table post-fingerprint was not collected after timeout and
is not claimed equal. Shared-source critical-row fingerprints did match.

The owned PG, Valkey and Vips processes exited; raw dump, datadir, socket and
sensitive work were removed. All 27,435 tracked original source blobs still match
the pin. Raw SQL/error HTML and new application-log data were discarded; sanitized
hashes/ownership/failure metadata and older failure history remain.

## Offline diagnosis and fix; no rerun

Character-indexed UTF-8 scanning in the new guard was superlinear on the actual
3,738,477-byte generated CSS/source-map INSERT. The lexer now uses `StringScanner`;
actual generated literals remain identical and scan in 0.0605 seconds. Synthetic
megabyte Unicode SQL is covered by a timeout-bounded regression, including a
trailing forbidden second statement. This offline fix does not change the failed
result or permit a second Rails experiment.

## Verification

Final logs: `build/recovery25-private-html-tests/final-*.log`.

- Private guard: 5 tests / 44 assertions, passing.
- Existing isolation: 18 tests / 133 assertions, passing.
- Exclusive usage and failure cleanup: 3 tests, passing.
- `make verify`: passing, `build/verify-20261107-183953`.
- Ruby syntax, Python compilation and `git diff --check`: passing.

Accepted supported native JSON proof150855 is preserved. Remaining work is
native HTML/preload/asset closure and real browser behavior. Write-free source
work may continue; another writable original reference experiment or any new
native/compat write requires fresh explicit authority.

## Executed write-free native frontend dependency after the failed reference

`make verify-ember-asset-graph` now compiles and executes a source-derived pure
manifest graph dependency under native Spinel and the same Ruby under CRuby,
compared with the full pinned original `EmberAssets` helper in a production
filesystem/environment test context. It does not boot a Rails application or
replace a controller, setting, permission, callback, or original PG effect.

The extracted graph code accepts a live parsed manifest; it is explicitly not a
complete `EmberAssets` replacement. Original request/production caches, build
status/error lifecycle, manifest acquisition and watcher remain outside this
pure dependency. The generator verifies original bytes, exact selected spans
and expected boundary transformations; provenance is committed alongside it.

Final executed proof: `build/ember-asset-graph-ijsgezx9/evidence.json`.

- Seven complete original/CRuby/native cases match, including the genuine built
  manifest, cycles, shared/diamond imports, order and duplicate suppression,
  dynamic entrypoint collisions, changed import-map input, missing imports,
  empty graphs and replay of the genuine manifest after changed inputs.
- The genuine manifest resolves 14 entrypoints and 53 import-map entries. All
  **53 genuine referenced asset files / 13,808,816 bytes** are actually read and
  SHA256-hashed identically under native and CRuby; no invented asset data.
- A real manifest with an empty asset directory fails before output under all
  three runtimes. Missing chunks in the graph retain the original helper's
  semantics; graph resolution alone is not proof of an existing asset.
- The traced native run has one execve and zero connects. No PG, shared or owned
  cache effect, private snapshot, or second Rails HTML experiment is involved.
- Native HTML, original HTML200, full layout/preload assembly and browser/page
  acceptance all remain false. This adds a concrete executed dependency, not a
  static substitute page or a new acceptance claim for the full ticket.
