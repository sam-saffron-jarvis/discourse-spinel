# Ticket 007 attempt-1 coordinator gate feedback

The gate log is `../ledger/gates/007-minimal-browser-1.log`. Its latest build and
native semantic smoke passed; browser startup then failed at the gate's plain bind
of loopback3498 with `EADDRINUSE`. No application change was needed.

## Socket ownership versus closed connections

A fresh owned `bash test/smoke.sh` reproduced this handoff:

- Native smoke passed and its child exited.
- `ss -ltnp` showed **no3498 listener**.
- Binding3498 without `SO_REUSEADDR` immediately failed with errno98.
- Binding the same port with `SO_REUSEADDR` immediately succeeded.
- The plain bind succeeded after60.536742s as the kernel's normal TCP `TIME_WAIT`
  entries expired; no process was killed to achieve it.
- A separate scoped live-listener fixture confirmed that the reuse-enabled probe
  still rejects an actively listening3498 socket with `EADDRINUSE`. It does not
  permit reusing somebody else's listener; `SO_REUSEPORT` is not enabled.

Evidence: ignored `build/gate-feedback/port-handoff.json` and `smoke.log`. This is
normal connection-close TCP behavior, not an owned native child leak. Production
HTTP close semantics should not be changed or reset merely to influence the probe.

## Real emoji titles versus raw DOM text

The attempt-1 gate also compared `a.title.textContent.trim()` directly to the API's
raw `title`. Actual pinned Discourse uses `fancyTitle()` in
`frontend/discourse/app/lib/topic-fancy-title.js`, calling `emojiUnescape()`: emoji
shortcodes become actual image elements. An image's alt text is not part of DOM
`textContent`, so a correctly rendered emoji title cannot pass that raw comparison.

An independent owned native run used the gate's installed Chromium1248 executable,
1280x900 desktop and390x844 phone viewports, and its `.main-link a.title` selector.
Both viewports rendered all20 live topics with correct semantic titles/links and
zero pageerrors/failed requests. The raw-text comparator alone missed one emoji
seed topic. The native API was unchanged; no literal shortcode was injected into
the app to satisfy the faulty comparator.

Evidence: ignored `build/gate-feedback/title-contract.json`, `desktop.png`,
`phone.png` and `native.log`. This is verification-only data, never a serving input.
`test/browser_smoke.py` now additionally records each link's `raw_title` and actual
emoji alt/src metadata alongside its semantic `title`, making the distinction
inspectable without weakening the existing ordered-ID/title/link/image assertions.

## Coordinator correction

During the resumed worker turn, the coordinator changed the protected
`harness/gates/minimal-browser.py` to:

1. Enable `SO_REUSEADDR` before the ownership-check bind.
2. Reconstruct emoji image labels from source Unicode metadata, compare semantic
   titles to `unicode_title`/`title`, and enforce live topic order/IDs.

The worker only read the harness and did not modify it. The application's source,
compiled ELF, actual Ember modules and latest JSON/security behavior remain
unchanged from integration commit `0b2a3a6`. The worker's own verification can be repeated with `make smoke` and
`make browser-smoke`; only the coordinator can rerun/record independent acceptance.
During the resume, the coordinator-owned `build/browser-gate/result.json` was also
observed with20 rows/topics and no pageerrors/failed requests for both viewports;
the attempt-1 ledger log still records the earlier bind failure. Those records
must be reconciled by the coordinator, not rewritten by the worker. The worker
has not controlled live3499 or shared `run/app.pid`.
