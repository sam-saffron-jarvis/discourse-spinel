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

## Source provenance (pinned reference)

Reference clone `discourse/` is at `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`.
No files in the reference clone were modified. The byte-identical application layout copy
under `minimal/frontend/reference/` is documented in its README; a separately marked
selected excerpt is at `minimal/frontend/application-shell.excerpt.html.erb`. No
Discourse runtime code was copied or adapted.

| Behavior | Pinned source | Source object ID |
|---|---|---|
| Document markup, setup metadata, preload script and mount point | `app/views/layouts/application.html.erb` | `b938cb0c9c750a66785dbe8cd2d70e3db97845f1` |
| Anonymous/common preload fields and JSON escaping | `lib/application_layout_preloader.rb` | `1a79d1c06aae3d730bb157f4e49aaa1329df6249` |
| `#data-preloaded` JSON encoding | `app/helpers/application_helper.rb` (`preloaded_json`, `client_side_setup_data`) | `b1ad18eb6cfe5cc1c0f7d14140fa612d763c78b1` |
| HTML preload key `topic_list` and JSON serializer route | `lib/topic_list_responder.rb` | `f994c03b38728aa8b02c7a04782c0230a0e127d7` |
| `topic_list` key | `app/models/topic_list.rb` (`preload_key`) | `8f5beaa95cdf8bcb28aa739fd8d0c72eb340f928` |
| Latest action/list semantics | `app/controllers/list_controller.rb` | `6f2908e6216fc1d15e93292f936483d5c96ea487` |
| Client preload parsing / fail-fast when no preload is present | `frontend/discourse/app/lib/preload-store.js` | `ab4167028286e8938f00258ea5ef9d6bc738d361` |

`minimal/build/assets/discourse/` now contains the generated core Ember browser modules,
manifest, source maps, and compressed variants (verified above); it is not a native
HTML response or complete Discourse asset installation. The large asset-processor JS
bundle in `discourse/tmp/asset-processor/` is build tooling, not a verified deployable
Discourse app bundle. No Rails asset build was started here. The remaining frontend
barriers are actual stylesheet delivery and a native HTML/bootstrap route with dynamic
safe site/settings preload data. Browser completion remains unproven.
