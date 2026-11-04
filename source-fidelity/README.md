# Original-source Discourse on Spinel — WIP snapshot

**Captured 2026-11-04T16:50:14.248738+11:00. This is unfinished source, not a working original native `/latest` release.**

The older adapted backend is preserved at the repository root. This directory contains the newer effort to execute original Discourse application bodies through reusable Rails compatibility and the Spinel native compiler. Original Discourse pin: `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`.

## Browse the current work

- [Source-fidelity probes and original-source locks](fidelity/)
- [Guarded source-context specialization](roundhouse/src/construction_contexts.rs)
- [Query-option framework primitives — active WIP](roundhouse/runtime/ruby/hash_options.rb)
- [Original query probe — active WIP](fidelity/tools/probe_original_query.py)
- [Positive anonymous security proof](fidelity/tools/verify_anonymous_security.py)
- [Full Roundhouse source/runtime/tests](roundhouse/)
- [Full task Spinel source/tests](spinel/)
- [Local changes against public component bases](changes/)
- [Unintegrated serialization and oracle lanes](parallel-lanes/)
- [Current result versus unproved work](STATUS.md)
- [Exact heads, dirty-file inventory and per-file hashes](SNAPSHOT.json)

## Exact snapshot components

| Component | Local source head | Snapshot state |
|---|---|---|
| `fidelity` | `afdb889e796d` | **includes uncommitted WIP** |
| `parallel-lanes/html-oracle/fidelity` | `ae1f17156bf2` | **includes uncommitted WIP** |
| `parallel-lanes/serialization/fidelity` | `8284bbde1fa4` | committed snapshot |
| `roundhouse` | `ab7bf5aafeec` | **includes uncommitted WIP** |
| `spinel` | `1c7339c664f8` | committed snapshot |

The snapshot copies actual working-tree source, including the listed uncommitted files. It does **not** silently claim those changes were committed or fully validated. The original source repositories and active worker were not reset, stashed, stopped or altered to make this publication.

`parallel-lanes/serialization/roundhouse.patch` is a separate, unintegrated change against the base recorded in `SNAPSHOT.json`; it is not already applied to the canonical Roundhouse snapshot. The lane Fidelity trees likewise preserve their own source state, rather than disguising them as one integrated passing application.

## What runs and what does not

The labelled anonymous category-security projection has passed native/CRuby/actual-Rails comparisons and negative controls. This is a small original-source foundation, **not full `TopicQuery#list_latest`, serializers, controller, document or browser execution**.

An independently guarded **original Rails oracle** rendered JSON and HTML successfully using real frontend assets and one explicitly approved disposable database copy. That provides reference dependency/effect coverage; it is **not native acceptance**. No oracle response is a runtime data source.

The current full native application still has framework/boot/plugin/serializer gaps. See [STATUS.md](STATUS.md). Fresh execution of this exact dirty snapshot has not passed a full application gate.

## Build and data boundary

These are source-browsing/development snapshots, not a fresh-clone turnkey installation. The original probes expect a pinned Discourse checkout, compatible Ruby/gems/Spinel toolchain and spinel-pg, and an appropriately prepared read-only database. They contain development-environment paths that need deliberate adaptation. No populated database, database dump, secret/config volume, model session, raw runtime trace, binary, generated frontend asset bundle or live-service state is included.

The private-PG oracle tool is opt-in and refuses to treat its recorded one-experiment authorization as renewable. Its published source does not authorize writes to anyone's database. Default shared-database guards remain read-only. Do not point the experimental harness at production data/services.

## Licensing and publication scope

Each component retains its own original license and notices: Roundhouse [MIT](roundhouse/LICENSE-MIT)/[Apache-2.0](roundhouse/LICENSE-APACHE), Spinel [original license](spinel/LICENSE), and Discourse-derived inputs [GPL notice](fidelity/LICENSE.txt). This layout does not relicense the bundled components. One directory of upstream HTTP capture fixtures was intentionally omitted to avoid republishing credential-shaped request data; exact omitted paths/hashes are recorded in the manifest. No active implementation code was removed for that exclusion.
