# Measured checkpoints

## Ticket011 — distinct anonymous per-post reaction summary

Base: accepted minimal `6f19f7d08bedc276841a2485c289a32737192e6f`.
Scope: native `GET /discourse-reactions/posts/:id/reactions-users[.json]`,
actual grouped summary source semantics, not010 users-list behavior. No compiler,
Discourse, live3499, Hub, database/settings writes or deployment changes.

| Measurement | Accepted010 baseline |011 local native build |
|---|---:|---:|
| Compiler inputs |29 files /244,185 bytes |30 files /255,936 bytes |
| Project inputs |23 files /137,467 bytes |24 files /149,218 bytes |
| Native ELF |2,280,760 bytes |2,336,448 bytes |
| Fresh build wall time (one observation) |15.490314s |16.472738s |
| Peak single-child/descendant RSS, not aggregate |401,972KiB |418,444KiB |

Same installed Spinel `2026.10.25+1664 (f969b32a7)`. Runtime metadata215,146
bytes, browser assets5,134 files /73,358,989 bytes and staged media334,448 bytes
unchanged. This is an expanded-program checkpoint, **not a speedup claim**.
Raw baseline/final observations: `build/reaction-summary/baseline-compile.json`,
`build/compile.json`; later rebuilds may vary in timing/RSS.

`make reaction-summary-test` passes18 native/source semantic cases using actual
source action/helpers with SELECT-only typed CTE dependencies and a process-local
frozen clock/settings. Eight visibility fixtures compare the actual source
fetch_post_from_params/Guardian with native statuses; denied summary calls cannot
issue reactor SQL and always roll back. Positive main/non-main/disabled/NULL/zero
values, source count-versus-cap27 behavior, historical main omission/merge,
first27-like reversal, descending reaction users, subsecond serialized ties,
name privacy, instance system avatar and strict undo-window boundary all pass.
Fresh actual Rails/plugin HTTP captures22 success cases plus9 denied/missing
cases, checked at root/prefix × profiler0/1 (including response-byte parity).
62 actual redacted SQL profiles are retained across the enabled modes. Native
credential/malformed/method/HTML boundaries, injection, profile state isolation,
ELF/no children and owned-port cleanup pass. Live global counts are0 reactions,
0 ReactionUsers and0 likes: **live empty-data parity**, separate from positive
source-driven fixtures, not positive live reaction evidence.

Full existing contracts also pass: plugin-test (8 source fixtures,48 fresh live
cases), smoke (10 native executables,20 latest and20 topic sources at first/near
windows), latest browser4 cases per profiler mode, topic browser16 cases per mode
with actual upstream SQL drill-down when enabled, profiler-test and injected502
visible error + Reload recovery. Latest/topic browser reports contain no page,
console, failed-request or HTTP errors. Warmed same-binary profiler HTTP medians
in this run: disabled1.924ms/enabled2.444ms; observed overhead, not speedup.
Logs `build/011-*.log`; private summary reports `build/reaction-summary/`.

Explicit narrower boundaries remain: anonymous JSON/XHR only, canonical32-bit
IDs and one bounded scalar reaction_value, credential/session auth403, plain
HTML shell501 versus source shell500, native error bodies, existing bounded
ASCII/default-avatar settings, no writes/other routes/plugin frontend/hooks or
all-core-plugin support. Source malformed/ignored-parameter and HEAD behavior
is captured honestly rather than mislabeled as native parity. See
`reference/reaction-summary-contract.md` and `GAPS.md`.


## Ticket 007 — actual native `/latest` browser list

Before: accepted minimal `42d8a13`, strict live latest JSON parity, HTML501 and
unintegrated core JS. After: native source-adapted document/preloads/static surface
renders actual core Ember topic rows at direct root and the configured widget
prefix. Topic content/full plugin support remain unimplemented. This larger
program is not a performance comparison with the previous JSON-only program.

### Final native build phase

Installed Spinel unchanged: `2026.10.25+1664 (f969b32a7)`. No whole-app compiler
input, compiler changes or optimization loop.

| Measurement | Verified value |
|---|---:|
| Fresh native build (`binary_rebuilt=true`) | 12.234150 s |
| Peak single child/descendant RSS, not aggregate | 370,664 KiB |
| Ruby compiler graph | 24 files / 193,613 bytes |
| In-repository graph, including vendored PG | 19 files / 95,125 bytes |
| Native ELF | 2,015,976 bytes |
| Runtime source metadata | 215,146 bytes: Unicode124,752 + settings90,394 |
| Staged browser files, including reused core JS | 5,134 files / 73,358,989 bytes |
| Privately staged avatar bytes | 334,448 bytes / 13 files |

Fresh-build evidence: `build/compile-cold.json`. The final `build/compile.json`
may describe a **cached** invocation (`binary_rebuilt=false`, approximately0.002s),
not a compiler speedup. These timings cover the native `spin build discourse`
phase only, excluding separate asset staging/oracle/browser work. Build metadata
now distinguishes binary rebuild/reuse and separately accounts source data/assets.

### Final verification

- `make smoke` passed: 9/9 native executables / 66 named checks. Original 28
  query/serializer/security checks preserved; new native checks cover source-safe
  settings, dynamic promotion, image-list refusal, script/attribute escaping,
  prefix/static MIME/traversal/symlink boundaries, avatar authorization, actual
  MessageBus ACL/backlog/transport and read-only banner visibility/order/data changes.
- Strict complete Rails latest JSON equality remains on20 first-page topics and
  empty page1. No allowlist/normalization;22 users/2 primary groups/2 flair groups.
- Read-only Site oracle: all14 emitted scalar/enum/menu/permission fields and every
  field in the ordered nine-public-category projection match actual Rails getters.
 390/390 emitted source client settings match the actual client API. Full parity
  remains false:375 additional client keys and315 aggregate category fields omitted.
- Actual aggregate `Site.json_for` is correctly blocked by its wizard setting
  INSERT under read-only PG; the exact stack is retained in `build/site-contract.json`.
  Safe field comparison uses actual getters, not stubs or write-enabled warmups.
- Actual MessageBus5 comparison exactly matches four live positions (-1,0,-3,ahead),
  with message counts1/8/2/1; native synthetic fixtures exclude private user/group/
  other-client data. Valkey uses DB0/logical multisite ID `default`.
- Additional MRI source tests:5 tests/68 assertions passing. Source/stage checks:
 110 source/vendor hashes, regenerable390-setting source catalog, unchanged layout/
  avatar palette reference,46 plugin entries,2,203 real icon IDs and4 font faces.
- PG seed remains34 topics/115 posts. No seed/DDL/shared-row writes; read-only
  typed CTE fixtures cover changed rows and privacy cases missing from the seed.

### Real browser evidence

`make browser-smoke` passed all four combinations. Both mounts render20 ordered
actual Ember `.topic-list-item` rows and real title links exactly matching live API
IDs/titles/links; title emoji images load. Each run loads2 module entry scripts.
Desktop observes74 responses/9 resolved icon uses; phone53 responses/8 icon uses.
All four have0 uncaught page errors,0 failed requests,0 HTTP≥400 responses and
0 console errors. No configured-prefix response escapes the mount. Typography is
Inter and actual base palette `--primary:#222`.

| Check | Viewport | Full-page screenshot |
|---|---|---|
| Widget prefix desktop | 1440×1000 | `build/browser/prefix-desktop.png` (1440×1883) |
| Widget prefix phone | 390×844 | `build/browser/prefix-phone.png` (390×1983) |
| Direct root desktop | 1440×1000 | `build/browser/root-desktop.png` (1440×1883) |
| Direct root phone | 390×844 | `build/browser/root-phone.png` (390×1983) |

`build/browser/report.json` records DOM rows, styles, module scripts, XHR payloads,
network/console/errors. Corresponding HTML/API/server logs are verification-only.
`test/browser_cleanup.py` interrupts a real rendered desktop run with SIGTERM;
exit143 and native3498 release passed (under0.2s shutdown in the final probe), then the full
proof is regenerated. The handler uses cooperative checkpoints because throwing
inside Playwright greenlets stranded close tasks in the initial cleanup probe.

Resolved first-browser gaps: emoji404s now serve real packaged Twemoji; core worker
404 now serves adapted actual source; MessageBus405 now reads real backlog/ACLs;
SVG namespace prefixes/incomplete palette initially hid icons/typography, now fixed
with actual symbols and guarded source palette/font compilation. No modified Ember
modules, Ruby-serving wrapper, captured preloads or handmade topic table.

---

# Ticket 004 measured checkpoint (historical)

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
