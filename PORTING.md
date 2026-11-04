> **Legacy adapted-backend document.** These counts/limitations describe the November2 root-level extraction, not the newer original-source work. See [current source-fidelity status](source-fidelity/STATUS.md).

# What was actually ported?

This is a **source-grounded native extraction of a small, read-only part of
Discourse**, not the complete Rails application compiling unchanged on Spinel.
The upstream Discourse checkout was not rewritten in place. Selected behaviour
was copied or adapted into a separate application; substantial server-side
functionality remains unported.

The source checkpoint described here is
[`fbc2d203cf6f7dfca42591c2f8493ee067cd6e07`](https://github.com/sam-saffron-jarvis/discourse-spinel/commit/fbc2d203cf6f7dfca42591c2f8493ee067cd6e07),
against upstream Discourse
[`96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`](https://github.com/discourse/discourse/tree/96ce8d44401a8a568ecc71561c26dca8ec6bfeb8).
Publication-only documentation is added on top of that source checkpoint.

## Unchanged versus adapted

| Area | Treatment |
|---|---|
| Core Ember frontend | Built from the pinned original Discourse source; not replaced by a custom topic-list/post renderer. Generated assets are not committed here. |
| Selected reactions frontend | **8 of 10** files in `frontend/reactions/` are byte-identical to files in the pinned upstream tree. The actions/counter caller and guest initializer are explicit read-only adapters. This is not the entire plugin. |
| Existing cooked post content | Read from the Discourse database. This extraction does not implement the full cooking, editor, or post-creation pipeline. |
| Topic-list and topic backend | Selected ActiveRecord/TopicView behaviour translated into explicit bound PostgreSQL queries and native JSON-record/serializer code. This is a manual adaptation, not unchanged Rails execution. |
| HTTP routing and document bootstrap | New native server glue and a source-derived document bootstrap. Includes prefix handling, bounded module loading, and a visible failure/reload path. |
| Site settings, preloads, avatars and MessageBus | Selected anonymous/read-only adaptations with narrower contracts and explicit gaps. |
| Reactions backend | Two selected read-only actions and topic metadata translated to native queries/serialization. No react/unreact writes or authenticated plugin runtime. |
| Details reader | Selected original Sass and existing core cooked-content behaviour for stored `<details>` markup. Not a Markdown cooker or editor/plugin-initializer port. |
| PostgreSQL driver | Separately vendored unchanged dependency; see its MIT notice. |
| MiniProfiler | Separate bounded native adapter/core with original upstream 5.0.0 browser assets, not a full profiler-feature port. |

The two adapted reactions frontend files are:

- [`frontend/reactions/components/discourse-reactions-actions.gjs`](frontend/reactions/components/discourse-reactions-actions.gjs)
- [`frontend/reactions/initializer-adapter.gjs`](frontend/reactions/initializer-adapter.gjs)

Every selected upstream source, original revision/hash and deliberate adaptation
is recorded in [`SOURCE_MANIFEST.json`](SOURCE_MANIFEST.json). Omitted behaviour
is documented in [`GAPS.md`](GAPS.md) and [`PLUGIN_SUPPORT.json`](PLUGIN_SUPPORT.json).

## Size of this server slice

At the source checkpoint above, these application/runtime Ruby files contain
**2,501 physical lines across 18 files**, or 2,182 lines after removing blank and
whole-line Ruby comments:

| Files | Physical lines |
|---|---:|
| `bin/discourse.rb` | 234 |
| `lib/*.rb` | 1,780 |
| `frontend/native_document.rb` | 291 |
| `reference/native_site.rb` (also loaded at runtime) | 196 |
| **Total** | **2,501** |

These counts include inline SQL, HTML, comments and data constants. In particular,
they include a 222-line file containing the unchanged selected letter-avatar
colour table in a renamed module. They exclude vendored runtime dependencies, generated metadata/assets,
source-reference copies, build tools, tests and the original Discourse codebase.
They are **not** a count of newly invented lines or a one-to-one diff against
upstream. Some methods preserve upstream logic within otherwise adapted files.

Reproduce the physical count from this checkout:

```sh
wc -l bin/*.rb lib/*.rb frontend/native_document.rb reference/native_site.rb
```

A separate Git-blob comparison against the pinned upstream tree finds **60
byte-identical tracked files**: 51 source-reference/test copies, eight selected
reactions runtime frontend files, and the GPL licence text. Reference copies are
retained for provenance and comparison; their presence does not mean the original
Rails controllers/models are running in the native executable.

## What the count does not mean

It would be misleading to say “only 2,501 lines had to change to port Discourse.”
This is a much smaller program with a much narrower feature set. Authentication,
posting/editing/deleting, most controller/model callbacks, background jobs,
complete serializers, full themes and most core-plugin behaviour are not ported.

The useful result is that this selected native backend can serve the **real
Discourse frontend** against the same database, with explicit read-only/source
comparison tests. It is not evidence that all of Rails or all of Discourse now
runs unchanged on Spinel.

## Evidence and reproduction limits

The implementation has source/native comparison tests and browser tests for the
supported subset. Positive reactions/details browser fixtures are labelled
separately from live database observations; the original test database had no
reactions or stored details examples. No fixture/oracle response is a runtime
substitute for native queries.

This public repository is currently a **source-browsing checkpoint**, not a
self-contained fresh-clone quickstart. Existing build/test scripts depend on a
sibling pinned Discourse checkout, an external development harness/toolchain,
already-prepared frontend/style inputs, and a populated task-owned PostgreSQL /
Valkey environment. Those services, local media, generated assets, database,
credentials and private test reports are intentionally not published.
