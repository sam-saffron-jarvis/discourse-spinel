# Source-grounded anonymous stored-cooked details reader (016)

Pinned source: Discourse `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`.
Unchanged source copies, paths and SHA256s: `details-sources/manifest.json`.
This is a bounded **reader** slice, not full discourse-details support.

## Source behavior and dependencies

- `plugin.rb` declares `enabled_site_setting :details_enabled` and registers
  `stylesheets/details.scss`. `config/settings.yml` declares a default-true,
  client-visible boolean. `Plugin::Instance#enabled?`, `Discourse.find_plugins`
  and `find_plugin_css_assets` select the stylesheet only for enabled plugins.
- The shipped `initializers/apply-details.js` registers a composer toolbar popup
  and rich-editor extension only. It has **no reader initialization**. It is not
  loaded; no replacement initializer or summary event-handler facsimile exists.
- The Markdown extension emits real `<details><summary>` HTML, supports `[details
  open]`, treats summary as text, and declares its sanitizer allowlist. Actual
  `PrettyText.cook` is used only as a build-time source oracle to generate labeled
  fixture cooked bytes. There is no native cooker port or runtime Ruby/Node.
- `BasicPostSerializer#cooked` and the existing bounded native topic adaptation
  return stored cooked for visible posts (existing hidden-post placeholder is
  preserved). Changing the plugin setting does not rewrite stored cooked. Even
  with plugin CSS absent, intrinsic browser details/summary still toggles: the
  setting is not invented post-content suppression.
- Original complete Sass is compiled through `Stylesheet::Compiler.compile_asset`
  and original `AssetProcessor`, not manually translated. The core color variables
  and `unselectable` mixin are resolved by that original compilation. Full original
  CSS contains editor selectors too; their presence is not editor support.
- Existing unchanged core Ember `PostCookedHtml` already runs
  `stateful-html-elements.js`: it assigns per-post detail IDs, retains open state
  across redecorations within that post component and opens on `beforematch` for
  core reveal behavior. No extra plugin reader JS is required. The core integration
  test explicitly covers retaining state across rerenders. Navigation destroys
  the post component's decorator state; unrelated posts must not inherit it.
  Quote-following/reveal is source context, not a newly claimed integration slice.

## Named adapters and boundaries

1. **Details stylesheet-selection adapter:** `frontend/stage-details.py` stages
   source/compiler dependency hashes and exact original compiled CSS;
   `stage-assets.py` integrates it with the existing static allowlist/manifest;
   `native_document.rb` honors its `enabled_setting` metadata. The generated client
   catalog and live typed settings reader include only actual source client data.
2. **Source-cooking/settings transport fixtures:** `test/details_source.rb` runs
   actual PrettyText.cook on labeled closed/open/nested/escaping/sanitizer cases;
   only process-local settings are overridden, never DB settings. The native
   fixture executable shadows tables using typed read-only CTEs, then executes
   actual native topic projection and tests unchanged cooked for both settings.
3. **Cooked-only JSON browser transport fixture:** `test/details_browser_smoke.py`
   fetches a real native topic response and changes only the first post's cooked
   field to the independently verified compiled fixture. All document/Ember/CSS,
   avatars, routes and native SQL remain real. This is labeled mocked transport,
   **not positive live-native end-to-end parity**. No DOM is injected as evidence.

Unsupported: composer/editor/Markdown cooking at runtime, email rewrite,
`reduce_cooked`/excerpts, complete plugin hooks/DSL, writes/auth, full serializer
coverage, and all-core-plugin support. Existing reactions010/011/015 boundaries
remain unchanged. See `GAPS.md` and `PLUGIN_SUPPORT.json`.

## Verification and evidence

`source ../harness/env.sh; make details-test` freshly rebuilds the own native ELF,
verifies provenance, generates actual source cooked fixtures, freshly compiles the
native CTE topic fixture, compares source/native settings/stored-content behavior,
and drives actual Chromium desktop/phone at root/widget prefix with profiler0/1.
Summary pointer/Enter/Space, closed/open visibility, original CSS pseudo-markers,
nested independence, route away/other/back and zero page/console/network errors
are required. Live cases retain real reaction metadata and enabled cases open the
original MiniProfiler SQL drilldown showing real redacted post/reaction PG SQL.

Evidence is private under `build/details/`: source/native fixtures and actual SQL,
read-only live inventory, live-native vs positive-transport browser reports,
screenshots/HTML, source/default/live settings checks and test logs. No live DB
seeding, DDL or settings writes. Empty live details inventory is reported as empty,
not used to claim positive live plugin parity. Existing smoke, reactions,
latest/topic/profiler and injected boot-failure+Reload targets remain independent
regressions; none are replaced or weakened by this test.
