# Bundled third-party notices

The main Discourse-derived application retains its original GPL-2.0-or-later
notice and licence. Dependencies and separately retained browser components keep
their own licences; this document does not replace or relicense them. See
[NOTICE.md](NOTICE.md) and the individual original licence files.

## Google Code Prettify inside MiniProfiler's browser vendor bundle

`vendor/rack-mini-profiler/html/vendor.js` contains Prettify code, in addition to
MiniProfiler's own MIT-licensed template/browser code. The Prettify component is
licensed under the Apache License, Version 2.0.

Original source attribution:

```text
Copyright (C) 2006 Google Inc.
```

The upstream distribution's COPYING additionally retains:

```text
Copyright 2011 Mike Samuel et al
```

The complete original notices and licence are preserved in:

- [COPYING](vendor/rack-mini-profiler/third-party/code-prettify/COPYING)
- [Original source licence header](vendor/rack-mini-profiler/third-party/code-prettify/UPSTREAM-LICENSE-HEADER.txt)
- [Notice-source revision, URLs and SHA-256 metadata](vendor/rack-mini-profiler/third-party/code-prettify/PROVENANCE.json)

These are accompanying publication notices. The existing bundled JavaScript and
MiniProfiler MIT licence have not been edited. All other dependency notices in
`NOTICE.md`, `vendor/`, source references and emoji attribution files remain.

## November4 source-fidelity snapshot components

The source snapshots under `source-fidelity/` retain their own notices and licensing. Roundhouse is dual MIT/Apache-2.0 (`roundhouse/LICENSE-MIT`, `roundhouse/LICENSE-APACHE`); Spinel retains `spinel/LICENSE` and the licenses/notices accompanying its packages and tests. Discourse-derived copied inputs retain GPL-2.0-or-later notices and `fidelity/LICENSE.txt`. Upstream included sources, fixtures and package notices are preserved. The repository layout does not relicense these components, and this is not a binary distribution. Exact source heads and working-tree contents are recorded in `source-fidelity/SNAPSHOT.json`.
