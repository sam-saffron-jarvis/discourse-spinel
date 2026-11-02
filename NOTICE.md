# Copyright and source notices

Discourse source and adapted definitions in this extraction:
Copyright 2014–2026 Civilized Discourse Construction Kit, Inc. and contributors.
Licensed under GNU GPL version 2.0 or later, as stated in the pinned Discourse
README. The GPL text is in `LICENSE.txt`. Original source paths, commit and
SHA-256 hashes, selected definitions and adaptations are in `SOURCE_MANIFEST.json`.
This is not an unchanged copy of Discourse or a complete plugin runtime.

The unchanged `discourse-details` plugin references and original compiled Sass
are MIT licensed, Copyright (c) Civilized Discourse Construction Kit, Inc.
The complete original notice is preserved at
`reference/details-sources/plugins/discourse-details/LICENSE`; its code, style,
settings, tests and notice retain source paths and hashes in the source manifests.
The existing core cooked/stateful reader dependencies retain the core GPL license.

`vendor/pg/` is unchanged runtime source from roundhouse-rb/spinel-pg 0.2.0,
commit `fe631b4ac4aba68168adf2ecce2c6c21006f7455`, Copyright (c) 2026 Sam Ruby,
MIT licensed; its full notice is preserved in `vendor/pg/LICENSE`.

`data/emoji-unicode.json` is generated from Unicode/name/alias/tone metadata in
Discourse's installed `discourse-emojis` 1.0.47 dependency (author Joffrey Jaffeux,
MIT according to the packaged gem specification), using Discourse's selected
`Emoji.lookup_unicode` algorithm. No emoji artwork is copied. The dependency's
original attribution file is retained at `data/discourse-emojis-attributions.md`.
The precise input hashes are in the source manifest; the generator never calls
Rails or queries a database.

Generated browser assets under ignored `build/assets/` use actual pinned Discourse
frontend source and installed dependencies, with their original distribution
licenses. They serve the real core Ember latest/topic UI; they do not establish
complete plugin/theme support. The copied application layout under
`frontend/reference/` remains byte-identical source, not rendered output; the native
document is a separately labelled adaptation.

`lib/message_bus.rb` adapts the read-only backlog/permission/transport algorithms
from `message_bus` 5.0.0, Copyright (c) 2012 Sam Saffron, MIT licensed. The complete
notice is retained in `vendor/message_bus/LICENSE`; no upstream dependency sources
were changed. The runtime adapter does not load Ruby MessageBus or start listeners.

The browser stage additionally copies actual Twemoji PNG artwork from
`discourse-emojis` 1.0.47 into ignored `build/assets/native/images/emoji/twitter/`
(the legacy public URL alias). Original art/package attribution is preserved in
`data/discourse-emojis-attributions.md`; stage manifest records every copied source
and SHA-256. This is separate from the artwork-free Unicode metadata transformation
above. No screenshot or captured Rails preload is an asset input.

`vendor/rack-mini-profiler/html/vendor.js` includes Google Code Prettify,
Copyright (C) 2006 Google Inc.; the upstream distribution's COPYING also retains
Copyright 2011 Mike Samuel et al. Prettify is Apache-2.0 licensed, separately from
MiniProfiler's MIT licence. Its full upstream licence, original source licence
header and notice-source revision/hash accompany the unmodified bundle in
`vendor/rack-mini-profiler/third-party/code-prettify/`. The accompanying notices
were added for publication; browser asset bytes and their original manifest
hashes are unchanged. See also `THIRD_PARTY_NOTICES.md`.

Foundation's generated palette references unchanged Inter and JetBrains Mono font
bytes from installed `discourse-fonts` 0.0.19. The stage manifest and source manifest
record the precise files and hashes; no font editing/subsetting is performed and
embedded original font naming/copyright/license metadata is retained.
