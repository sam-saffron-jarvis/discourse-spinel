# Native `/latest` frontend integration contract

This note records the real Discourse browser bootstrap required by the minimal native
server. It is a contract, not a substitute template or an alternate renderer. The
native proof must return native-generated document/preload data and serve browser
assets; Rails may be used only as the pinned source/reference, never as a data proxy.

## Required request/response surface

1. `GET /latest` (also at the configured widget prefix) returns the actual SPA document
   shape: `html`, `<head>` metadata and stylesheets, `#data-discourse-setup`, the
   `#data-preloaded` JSON script, and the module entry script. `<section id="main">`
   is the Ember mount point; do not replace this with a server-rendered topic table.
2. The document's `#data-preloaded` text is an outer JSON object keyed by preload name;
   each value is itself JSON text. `populatePreloadStore()` parses the outer object,
   then parses each value and stores it by key. For an anonymous latest page, required
   keys are:
   - `site`: `Site.json_for(guardian)` serialized site/brand/category data;
   - `siteSettings`: client-visible site settings;
   - `themeSiteSettingOverrides`, `customHTML`, `banner`, `customEmoji`,
     `isReadOnly`, `isStaffWritesOnly`, `activatedThemes`, `upcomingChanges`;
   - `topic_list`: `TopicListSerializer` output for the live latest query.
   An authenticated response additionally has `currentUser`, `topicTrackingStates`,
   and `topicTrackingStateMeta` (plus role-specific preloads where applicable).
   Do not guess these values from fixtures: the backend owns generation and visibility.
3. The actual initial `/latest` route consumes `topic_list` from the preload store; the
   route's API refresh/pagination path needs `GET /latest.json` returning the JSON form
   of the same `TopicListSerializer` result (including pagination URLs/metadata). The
   HTML bootstrap is not satisfied by JSON alone.
4. Resolve each CSS/JS URL from the compiled Discourse asset manifest/asset processor,
   then serve it under the same native/widget prefix with correct MIME types. The
   document must include `discourse` as an ES module, its import map/modulepreloads,
   locale module preload(s), `js/browser-detect`, `js/browser-update`, and the
   stylesheet(s) selected for this document. Preserve query/hash/version values and
   relative URL prefix. Asset URLs are build outputs, not hard-coded Rails hashes.
5. Carry `#data-discourse-setup`'s `data-*` values used by the client, at minimum
   `base-url`, `base-uri`, `environment`, `default-locale`, `asset-version`,
   `service-worker-url`, `letter-avatar-version`, `svg-sprite-path`, and theme/CSS
   configuration. Values must agree with the app's configured prefix and native host.

Native backend prerequisite: provide these as **dynamic, guest-visible output** from
native code. `siteSettings` must match Discourse's client-safe
`SiteSetting.client_settings_json` contract; never dump raw settings rows or include
secret-valued settings. Likewise, `site` must implement the required client-facing site
shape, not reuse a captured oracle payload. This is a substantive backend contract and
may be the next blocking parity item; source/template assets alone do not satisfy it.

The `/latest` document bootstrap must not depend on a browser-side Rails proxy or
Rails-hosted API data. Any additional XHR the browser actually makes must be observed
and implemented natively before claiming a working page.

## Oracle-data and secret handling

This contract records field names and source-code provenance only; it contains no
captured Rails response, session/cookie/CSRF value, or site-setting value. Do not check
in captured preload payloads or browser/session traces: `siteSettings` may include
sensitive configuration. If a local oracle capture is needed for comparison, keep it
out of version control, restrict it to the task-owned local environment, and redact
secret-valued settings and all auth/session/CSRF material before producing any report
or artifact. Provenance should identify source paths and pinned object IDs, never
quote oracle response values.

## Build feasibility and isolated command

Use the owned wrapper from the repository root after loading the task harness:

```sh
source harness/env.sh && minimal/frontend/build-ember-assets.sh
```

It stages only `discourse/frontend/discourse` under `minimal/build/.frontend-ember-stage`,
uses already installed package dependencies through links, runs production Rolldown with
a hard 600-second timeout, and publishes the resulting core Ember modules/manifest to
`minimal/build/assets/discourse/`. It does not download packages and refuses to
overwrite an existing output. It removes its staging tree on exit. It is JavaScript
assets only: it does not create an HTML response, CSS, plugins, theme bundles, or a
working native `/latest` page.

The wrapper has been run successfully on the pinned source: Rolldown produced the
`discourse` and worker entrypoints plus 53 manifest chunks in about 7 seconds, totaling
about 59 MiB including source maps and compressed variants. It writes only under
`minimal/build/assets/discourse/`; the Discourse working tree remained unchanged.
This output proves the JS compiler works, not that the browser boots.

The full Rails asset task is not an isolated command: `discourse/lib/tasks/assets.rake`
attaches asset work to the Rails `environment`, the Ember build writes
`discourse/frontend/discourse/dist`, plugin compilation writes
`discourse/app/assets/generated`, and Rails/Sprockets publishes into
`discourse/public/assets`; CSS precompile may query the Rails database and writes
`discourse/tmp/stylesheet-cache`. Therefore it cannot meet the no-Discourse-tree-write
constraint as-is. After the JS output exists, the next bounded integration step is to
implement or request an approved, non-Rails stylesheet stage whose source inputs,
asset URLs, and target directory are explicit; do not run `bin/rake assets:precompile`
against the pinned clone for this task.

## Frontend helper stage (Ticket 007)

Run from the run root after loading `harness/env.sh`:

```sh
python3 minimal/frontend/stage-assets.py
```

This is an isolated stage and **does not rebuild JS**: it requires the already-built
`minimal/build/assets/discourse/manifest/manifest.json` and reuses those core Ember modules.
For Foundation palette output, it invokes a bounded Rails runner only to call the source
compiler in a read-only transaction; it is not a Rails server or asset-precompile task.
The runner is guarded against AssetProcessor builds as described below. All deliberate
stage output is under `minimal/build/assets/native/`; no pinned Discourse source/generated
asset files are edited. Existing generated output is source/output-hash verified before a
normal rerun replaces it. Inspect `minimal/build/assets/native/manifest.json` for exact
staged paths, SHA-256s, source paths, manifest mappings, and honest limitations. The
manifest's root URLs are logical paths; compose each with the request's configured `base_uri`.
The core entrypoint/import-map values are files beneath `build/assets/discourse/` and must be
served with JavaScript MIME types. The descriptor also stages the pinned
`frontend/discourse/scripts/js/browser-detect.js` and `browser-update.js` sources at
`/assets/native/js/`; use those paths rather than expecting Rolldown to include them.
Static server path validation remains the native server's responsibility.

The stage copies the pinned checkout's existing generated `discourse/tmp/stylesheet-cache`
`common_*.css` output. It also uses a **direct, isolated** call to the pinned
`Stylesheet::Compiler.compile_asset(:color_definitions, theme_id: -1, color_scheme_id: ColorScheme.base.id)`
for Foundation's actual palette and font declarations. Before any Rails runner starts, the
stage overwrites inherited connection variables with task-owned `DATABASE_URL`, `REDIS_URL`,
PG host/port/user/database and `PGOPTIONS=-c default_transaction_read_only=on`, then asserts
PG identity/read-only status with `psql` and Valkey port identity with read-only `redis-cli
INFO server`. The runner verifies those identities again and wraps database reads in a
read-only transaction. It writes compiled output only under `minimal/build/assets/native/`.
Before compiling, it computes the current `AssetProcessor::BUNDLE` source digest, requires
the exact matching precompiled `tmp/asset-processor/asset-processor-<digest>.js`, and
reuses that file directly; it overrides the runner's processor-source accessor so a stale
or absent bundle cannot trigger a rebuild. The digest and cache SHA are in the descriptor.
No stylesheet Builder/precompile task runs. Common CSS is real compiled output, not
hand-authored, but remains a checkout cache artifact. There is **no** default Foundation
`-1` common/desktop/mobile theme CSS cache; the only theme cache found was Horizon `-2`
and it is deliberately excluded. Pinned `common.scss` is unified core CSS (no separate
core `desktop.scss`); the generated Foundation palette and actual Inter/JetBrains Mono
font files complete the visible core styling. Theme-specific common/desktop/mobile CSS
remains a gap and is recorded in the descriptor. Font URLs are rebased to paths relative
to the staged palette stylesheet so the configured mount prefix is preserved.

English client locale JS is derived from pinned `config/locales/client.en.yml` and the date
formats in `server.en.yml`, without Rails/site data/plugin merges/custom overrides. It
provides `configureMoment()` required by `app/lib/load-moment.js` and a valid
`messageFormatData()` callback for I18n startup, but its message-format callback returns an
empty bundle and `_MF` entries are omitted. This is an explicit translation gap, not a
full Rails-generated locale bundle. The icon sprite is assembled from original
`vendor/assets/svg-icons/**/*.svg` symbols using runtime IDs from `SvgSprite`; plugin and
theme icons are omitted. The staged logo/avatar/favicon files are copied from pinned
`public/images/`.

The stage also copies the pinned `discourse-emojis` 1.0.47 `dist/emoji/twemoji` tree to
`build/assets/native/images/emoji/twitter/` (Twitter is the public legacy URL alias).
This resolves the observed `/images/emoji/twitter/wave.png?v=16` and
`speaking_head.png?v=16` requests; the browser/native route should serve `/images/*` from
that staged tree and ignore query parameters for file lookup. Per-file source hashes are
in the descriptor.

`service-worker.js` is a source-derived adaptation of pinned
`app/views/static/service-worker.js.erb`, not a fake/no-op worker. The stage substitutes
only the two `Discourse.base_url` and one `Discourse.base_path` ERB expressions with
`__MINIMAL_BASE_URL__`/`__MINIMAL_BASE_PATH__` placeholders and removes the Rails plugin
worker registry block. Serve it at `${base_uri}/service-worker.js` after expanding those
placeholders from the trusted configured `origin + base_uri` and `base_uri`; the pure Ruby
reference method is `NativeDocument#render_service_worker(origin)`. The native service
route must perform the same substitution (or port that method), with JavaScript MIME.
Plugin worker hooks are an explicit omission; the core push/share/notification behavior
is retained. Source/output hashes and adaptation notes are in `manifest.json`.

### Native document/bootstrap handoff

The parent server can implement the following pure-input API (no Rails invocation):

```text
NativeDocument.new(base_uri).render(preloads, settings, origin)
```

- `base_uri`: empty string at direct root or a normalized leading-slash mount path, no
  trailing slash (for example `/node/jarvis/widgets/discourse-spinel-app`). Use it for
  **every** document asset URL, setup `base-uri`, links, and native endpoint references.
- `preloads`: a Hash of preload key to the backend-produced JSON **text** for that value.
  The document outer preload object is JSON encoding of those strings (not a nested object).
  Require dynamic backend fields and preserve the source preloader's key names. Ensure
  each encoded JSON string and the containing script are safe against `</script>`; the
  pinned helper replaces `</` with `<\\/` in each preloaded value before `to_json`.
  Never insert a Rails capture or raw settings rows.
- `settings_hash`: safe client site settings from the backend contract, not setup metadata.
  This renderer reads only `default_locale` (falling back to `en`) to select the document
  language; it never dumps the hash to `<meta>` or substitutes for the `siteSettings`
  preload.
- Setup attributes are constructed explicitly from source-derived runtime defaults:
  `base-url` = trusted `origin + base_uri`, `base-uri` = configured prefix,
  `environment=production`, `default-locale`, asset version derived from the built core
  manifest, `service-worker-url=service-worker.js`, `letter-avatar-version=5`, staged
  `svg-sprite-path`, `user-color-scheme-id=-1`, `user-dark-scheme-id=-1`,
  `is-staff=false`, and related safe defaults. The letter-avatar version uses the pinned
  algorithm version only; the dynamic image-tool suffix is not modeled yet.
- `origin`: use trusted `MINIMAL_ORIGIN` when configured, otherwise derive the direct
  listener origin from its configured bind address/port (e.g. `http://127.0.0.1:3498`).
  Normalize to scheme+authority only; `base_url` is `origin + base_uri`. Do not accept
  arbitrary Host/X-Forwarded-Host values as trusted public URLs; current widget forwarding
  sends Host localhost and X-Forwarded-Proto https. An explicitly configured public origin
  is needed for proxy-host-aware absolute URLs.

The document follows the pinned `app/views/layouts/application.html.erb` shape: HTML
`lang`/head metadata; setup meta; percent-encoded JSON from
`ApplicationHelper#discourse_config_environment` in `meta[name="discourse/config/environment"]`
(with `rootURL` set to the prefix); `discourse-assets` with CSS links inside
`discourse-assets-stylesheets`, JSON preload script, and icons; `<section id="main">`;
module entry script `discourse`; and deferred `js/browser-update`. The setup hash does not
contain arbitrary client settings. Use the descriptor's entrypoint and `importMap` mappings
to generate import-map entries where each key is the **absolute prefixed stable URL**
(the real chunk URL with its filename replaced by the stable filename) and each value is
the corresponding absolute prefixed real URL, matching
`ApplicationHelper#generate_import_map`. Modulepreload the dependency closure from `chunks`
for `discourse`, as `EmberAssets.deep_imports_for` does. Include the staged browser-detect
and browser-update scripts, and load the staged English locale script. Link each descriptor
CSS URLs; the Foundation palette is staged. Theme-specific common/desktop/mobile
CSS is not extracted (the pinned precompiler skips Foundation -1 theme CSS).
`svg_sprite_path` points at the staged real core-symbol bundle.

Pinned source contracts and blobs: layout `b938cb0c9c750a66785dbe8cd2d70e3db97845f1`;
preloader `1a79d1c06aae3d730bb157f4e49aaa1329df6249`; `client_side_setup_data`,
`generate_import_map`, and script path helpers in `app/helpers/application_helper.rb`;
manifest/import-map and transitive module traversal in `lib/ember_assets.rb`; client locale
output semantics in `lib/js_locale_helper.rb`; SVG path/bundle in `lib/svg_sprite.rb` and
`app/controllers/svg_sprite_controller.rb`. The parent owns server integration, request
routing, native API/static path/MIME/traversal tests, and browser testing. This staged
contract alone does not establish browser success; the combined proof is below.

Reference clone `discourse/` is at `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`.
No files in the reference clone were modified. The byte-identical application layout copy
under `minimal/frontend/reference/` is documented in its README; a separately marked
selected excerpt is at `minimal/frontend/application-shell.excerpt.html.erb`. The
reference layout remains unchanged; the live native adapters are separately labelled
in `SOURCE_MANIFEST.json` and `GAPS.md`.

| Behavior | Pinned source | Source object ID |
|---|---|---|
| Document markup, setup metadata, preload script and mount point | `app/views/layouts/application.html.erb` | `b938cb0c9c750a66785dbe8cd2d70e3db97845f1` |
| Anonymous/common preload fields and JSON escaping | `lib/application_layout_preloader.rb` | `1a79d1c06aae3d730bb157f4e49aaa1329df6249` |
| `#data-preloaded` JSON encoding | `app/helpers/application_helper.rb` (`preloaded_json`, `client_side_setup_data`) | `b1ad18eb6cfe5cc1c0f7d14140fa612d763c78b1` |
| HTML preload key `topic_list` and JSON serializer route | `lib/topic_list_responder.rb` | `f994c03b38728aa8b02c7a04782c0230a0e127d7` |
| `topic_list` key | `app/models/topic_list.rb` (`preload_key`) | `8f5beaa95cdf8bcb28aa739fd8d0c72eb340f928` |
| Latest action/list semantics | `app/controllers/list_controller.rb` | `6f2908e6216fc1d15e93292f936483d5c96ea487` |
| Client preload parsing / fail-fast when no preload is present | `frontend/discourse/app/lib/preload-store.js` | `ab4167028286e8938f00258ea5ef9d6bc738d361` |

## Combined native browser proof (ticket 007)

`make browser-smoke` now runs the actual native document/data/static surface with
these core modules and staged assets. Root and configured widget-prefix runs each
pass desktop1440×1000 and phone390×844: 20 actual Ember `.topic-list-item` rows,
ordered IDs/titles/`a.title` links exactly matching the live native PG API, real
loaded title emoji, resolved SVG symbols, Inter typography and source palette.
Each run loads two module entry scripts and has zero uncaught page errors, failed
requests, HTTP responses ≥400 or console errors. No prefixed-run response escapes
the configured mount. Screenshots/DOM/network logs are in `build/browser/`.

The target first interrupts an actual desktop-rendering browser with SIGTERM and
verifies that its own native3498 child is released; full browser evidence is then
regenerated. No shared3499 process/widget/supervisor is changed. Existing widget
source forwards its already-stripped `self.path` unchanged; native routing accepts
both stripped and full-prefix input. This is local native proof, not a live public
widget deployment claim.

Core Ember modules are unmodified. The large cached AssetProcessor bundle remains
build tooling only; the palette compiler uses its exact checked digest and cannot
rebuild it. Common cached CSS's root/reference-host image URLs are rebased relative
to the staged CSS, with separate original/output hashes in the stage descriptor.
No Ruby/Rails process serves the application. Topic content, complete plugin/theme
behavior, full Site/client-settings parity and compiled MessageFormat translations
remain explicit gaps; see `../GAPS.md` for each boundary.
