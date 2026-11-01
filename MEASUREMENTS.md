# Ticket 004 measured checkpoint

## Scope / result

Before this ticket: README/license-only minimal repository; no native backend.
After: native PostgreSQL-backed anonymous latest JSON, exactly equal to Rails on
the current seed for both requested pages. **Browser `/latest` is not complete**;
normal HTML requests return 501. Topic pages and full plugins remain unimplemented.

## Backend build

Installed compiler: `spinel 2026.10.25+1664 (f969b32a7)`; no compiler repo changes.

| Measurement | Final verified value |
|---|---:|
| `spin build discourse` wall time | 9.090100 s |
| Peak single child/descendant RSS | 365,940 KiB |
| Ruby compiler input graph | 15 files / 148,936 bytes |
| In-repository portion, including vendored PG | 12 files / 63,175 bytes |
| Native ELF bytes | 1,683,304 |
| Runtime Unicode metadata bytes | 124,752 |

RSS is `getrusage(RUSAGE_CHILDREN).ru_maxrss`, the maximum single-child peak,
**not summed parallel-process memory**. The graph counts Ruby inputs, not bundled
precompiled native runtime objects. Raw evidence: `build/compile.json`,
`build/load-graph.txt`, `build/compile.stderr`, `build/bin/discourse`.

The first tiny count-only server built in 6.856582 s / 348,888 KiB peak and returned
live count 34. That was a different program and is not a speedup comparison. The
final program performs the actual scoped query/serialization/permission work.

## Verification

`make smoke` passed:

- 3/3 native regression executables, 28 named checks: SELECT-only CTE security,
  ordering, global/local pin behavior, pin-adjusted multi-page results, changed
  source-data order, NULL category semantics, serializers, settings/user/emoji data.
- Fresh synchronous Rails capture with `PGOPTIONS` default read-only and explicit
  read-only transaction, followed by an owned native port-3498 listener. Full JSON
  equality, no allowlist, for 20 first-page topics and empty page 1. Root payload:
  22 users, 2 primary groups, 2 flair groups, and the topic list.
- Existing seed security: six restricted-category topics excluded, including
  ordinary topic 22; all 11 category definitions excluded with current setting.
  Seed has no deleted/unlisted/private-message examples; synthetic CTEs cover those.
- HTTP tests cover JSON negotiation, canonical pagination URL variants, invalid
  filters/page inputs, unsupported method/route, explicit HTML 501, and a subsequent
  good request. Listener is killed/waited by trap; neither 3498 nor 3499 remains bound.
- 55 source/vendor hash checks, unchanged copied layout/palette, and all 46 plugin
  entrypoints represented in the honest partial-support ledger.
- Shared DB counts before/after remain 34 topics / 115 posts. No shared DB writes,
  DDL, reset or seed operation was used. No Rails HTTP data-serving process exists.

Exact fields and supported/missing behavior: `GAPS.md` and `reference/latest-contract.md`.

## Frontend build, not browser boot

Parent independently reran `frontend/build-ember-assets.sh`: 7.992232 s wall,
182 output files / 60,582,910 bytes. Manifest: 2 entrypoints, 12 dynamic entrypoints,
53 chunks and 53 import-map entries. Rebuilt manifest is byte-identical to helper
output; SHA-256 `a7740ead545f1d7941a18692b5f79e7f01cf4e3f6bff7e5d944b6332f7939265`.
Raw evidence: `build/frontend-build.json`, `build/frontend-build.log`,
`build/assets/discourse/manifest/manifest.json`. Reference Discourse tree unchanged.

Missing: native dynamic safe site/settings preloads, document/bootstrap/setup/import
map/static routing and CSS/locale/icon/plugin/theme delivery at widget prefix.
The reference Rails HTML route also returns 503 without its frontend manifest; no
HTML parity or browser DOM result is claimed. `frontend/INTEGRATION.md` and README
specify the exact next browser task and coordinator-only launch instructions.

## Resolved failures / remaining blocker

- `/usr/bin/time` is absent; measurement uses Python `resource`/monotonic time.
- Spin's git `ref` does not accept a detached SHA (clone treats it as a branch).
  Runtime-only PG source is vendored unchanged at its verified commit instead.
- Initial group/thumbnail SQL assumed nonexistent physical columns; corrected
  from source to derived flair URL and thumbnail `upload_id` association. Semantic
  regressions and final smoke pass. No compiler fix was needed.
- A new emoji test incorrectly expected `tm` absent; source gem maps `trade_mark`
  alias to `tm`, so the assertion now checks the actual source behavior.
- Remaining blocker: missing native browser preload/document/stylesheet integration,
  not compile latency. No whole-app compiler optimization was resumed.
