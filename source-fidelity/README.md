# Original-source Discourse on Spinel — committed WIP checkpoints

**Captured 2026-11-09T13:40:02.820758+11:00. The complete native `/latest` page is not accepted.**

This is the active source-fidelity migration. The repository root retains the older
manual/adapted backend; it is not proof of this implementation.

## Current committed sources

| Component | Exact commit |
|---|---|
| `fidelity` | `e6969aaae09671a1f59ed6de14bce92ccc714a63` |
| `roundhouse` | `e37a1767322147cbcaccc45af53f09920066e201` |
| `spinel` | `a1a1bea71e148d4fbd7350dbbb79d9dc36840feb` |

- [Fidelity application projections, probes and regression tests](fidelity/)
- [Roundhouse reusable Rails compatibility](roundhouse/)
- [Spinel compiler and runtime](spinel/)
- [Status and limitations](STATUS.md)
- [Publication policy](PUBLICATION.md)
- [Exact per-file hashes and provenance](SNAPSHOT.json)
- [Component deltas against recorded public bases](changes/)
- [Historical, unintegrated November 4 helper lanes](parallel-lanes/)

Active components are exported from immutable committed Git trees. Uncommitted
and untracked live work is intentionally excluded. Components are pinned
independently; a snapshot is not an atomic integration test or release.
Historical helper lanes retain their original capture metadata and are not
silently promoted into the canonical implementation.

Builds require the pinned Discourse source, compatible toolchains/dependencies and
an appropriately prepared read-only database. No populated database, dumps,
credentials, raw request captures, sessions, binaries or generated asset bundle
are published. This is not a turnkey production installation.

Original source pin: `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. Dependency licences and
notices remain in their component directories. Roundhouse's upstream HTTP capture
fixture directory is omitted; hashes of excluded members are in the manifest.
