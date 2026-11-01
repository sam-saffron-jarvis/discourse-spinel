# Copyright and source notices

Discourse source and adapted definitions in this extraction:
Copyright 2014–2026 Civilized Discourse Construction Kit, Inc. and contributors.
Licensed under GNU GPL version 2.0 or later, as stated in the pinned Discourse
README. The GPL text is in `LICENSE.txt`. Original source paths, commit and
SHA-256 hashes, selected definitions and adaptations are in `SOURCE_MANIFEST.json`.
This is not an unchanged copy of Discourse or a complete plugin runtime.

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
licenses. They are build evidence, not a claimed completed browser application.
The copied application layout under `frontend/reference/` is byte-identical source,
not rendered output; its provenance is recorded alongside it.
