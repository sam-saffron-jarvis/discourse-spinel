# Latest JSON request work — no native request acceptance yet

`ee6671f` remains the accepted full-serialization checkpoint. This directory is a
separate, explicitly unaccepted controller/request increment.

Shared source generation (`tools/generate_latest_json_request.rb`) expands the
actual fixed `:latest` action. Its JSON component executes the real TopicQuery,
paging helpers, TopicListSerializer and framework renderer. Page-only metadata
is deferred, and non-JSON requests retain the original action through `super`.
The full candidate ListController and its inherited callbacks remain in place.
The real default current-user provider has a guarded no-credentials profile:
credential/query/preauthenticated contexts explicitly refuse rather than silently
becoming anonymous. Broader authentication is not claimed.

The original/shared Rails regression is reproducible:

```sh
source harness/env.sh
export CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4
taskset -c 0-3 python3 fidelity/tools/probe_latest_json_rails.py
```

It exercises genuine routes/middleware/controllers for the default latest list,
three two-row pages, ascending created order and invalid-page HTTP400. It compares
all payload fields/types, paging links, status and **every header**. The sole
nondeterministic field, X-Request-Id, is retained raw and independently validated
as a UUID, not compared for identical random bytes. Content-Length is not dropped;
real recursive `as_json` plus JSON.generate preserves original response bytes
(including unescaped ampersands) where the initial encoder attempts did not.
3558 setting/accessor observations and original constructor records still match.

These are Rails/reference tests, not a native controller request, browser page,
full-plugin acceptance or permission to omit callbacks in a native request.
The next experiment must compile AND RUN the bounded native controller closure
on actual framework request/response, use identical lowered CRuby, and retain
cumulative earlier-stage proofs. All acceptance flags in this source manifest
remain false until that separate execution and full parity succeed.

## Recovery21 executed middleware checkpoints (Nov6)

Request acceptance remains **false**. The current shared/native stack restores
8 of the 35 original development-stack middleware classes, with 27 still explicitly
unaccepted. Neither matching JSON nor this inventory is page/browser acceptance.

- `probe-portable-security-20261106-135438`: 17 complete three-way responses,
  62 request controls; genuine request-ID context before controller entry.
- `probe-portable-security-20261106-142244`: CORS enabled via actual independent
  environment providers; 20 complete three-way responses and 70 request controls.
- `probe-portable-security-20261106-142925`: ambient configuration (CORS disabled
  here); the same 20 complete responses and 66 controls, no injected CORS headers.

All retain earlier query/serializer/security controls, direct ELF execution,
exactly two read-only PG connections and one owned cache connection, no Ruby child,
and verified fixture cleanup. Their final **nonzero** result is intentional: the
remaining original middleware obligations are not implemented/accepted.

```sh
source harness/env.sh
export CARGO_BUILD_JOBS=4 BUNDLE_JOBS=4
taskset -c 0-3 python3 fidelity/tools/probe_latest_json_request.py
taskset -c 0-3 python3 fidelity/tools/probe_latest_json_request.py --cors-configuration enabled
```

The enabled option supplies public test origins and enablement only through the
real GlobalSetting environment-provider inputs in each independent process. It
never substitutes a settings getter, changes a DB setting, or supplies captured
oracle runtime values. CORS origin normalization, allowed/disallowed-origin fallback,
credentials/header declarations and the real pre-controller env are compared.
Omitted middleware and wrong response origins are rejected. Unsupported nonboolean
enablement/numeric origins refuse through exact shared guards with zero profiler
writes. Global-configuration hot reload with an already-constructed Rails stack is
not claimed from these fixed-process configuration tests.

`fast_blank` matters: original Discourse loads its C `blank?` override (ASCII
whitespace or NUL), not ActiveSupport's Unicode `blank_as?`. The generic Rails
request-ID adapter retains Rails semantics; the shared Discourse component uses
the real application override. Both contexts are tested against original methods.
Supplied request IDs, including present-but-sanitized-empty NBSP, are asserted and
compared **exactly**; only genuinely generated UUID randomness is normalized.
A late response-only UUID is rejected even with an otherwise matching response.
