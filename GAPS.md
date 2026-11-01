# Minimal extraction gaps — native `/latest` browser checkpoint

This is a scoped native **anonymous latest** extraction, not a compiled Rails
application. `SOURCE_MANIFEST.json` distinguishes source adaptations and runtime
adapters. No captured Rails response/preload is a runtime input.

## Implemented and verified

- Real Spinel-produced ELF, loopback TCP HTTP, live pure-native PG driver and
  read-only transactions. Only task PG5499/Valkey6399 are accepted.
- Accepted default `/latest.json` ordering, anonymous visibility and complete seeded
  serializer projection remain unchanged: strict Rails equality on two pages,
  SELECT-only synthetic security/pagination fixtures, no field normalization.
- `/latest` and `/` serve source-adapted Discourse document/setup/import-map and
  dynamic `topic_list`, safe `site`/`siteSettings` and common preloads. Core Ember
  modules render the actual `.topic-list` and `a.title` links; no handmade table.
- Root and configured `MINIMAL_BASE_URI` document/module/asset/link routes. Both
  prefixed requests and proxy-stripped requests are accepted at segment boundaries.
- Canonical staged public static paths, explicit MIME allowlist, binary lengths,
  no source maps/compressed variants/JSON manifests/dotfiles/traversal/symlink escapes.
- Bounded actual MessageBus5 short polling reads live Valkey backlog/positions and
  applies source anonymous user/group/client ACLs. Exact live comparison to the
  actual Ruby implementation at four positions; no canned empty response.
- Native source-derived client-settings catalog: 390 safe core fields with typed
  live overrides, source upcoming-change default promotion and upload URL lookup.
  The internal promotion threshold is read live but is not exposed as a client
  setting. Every emitted setting matches the read-only Rails client API on this DB.
- Every emitted Site scalar/enum/menu/permission field and ordered public category
  projection matches actual read-only Rails getters. Full Site/category parity is
  explicitly **not** claimed.

## Deliberate divergences and missing scope

| Path | Construct | Boundary / why | Required work |
|---|---|---|---|
| `reference/native_site.rb` | Full `Site.json_for` / `SiteSerializer` | Narrow anonymous projection. Nine public categories omit 315 serializer fields in aggregate. Group/sidebar/auth-provider/tag/color-scheme/access-control/user-field/plugin metadata is not extracted. Permission booleans reflect tested default anonymous configuration, not full dynamic Guardian/plugin policy. | Extract remaining source fields/guards with read-only oracle tests; never use captured Site JSON. |
| `reference/site-oracle.rb` | Aggregate Rails oracle write-on-read | Actual `Site.json_for(Guardian.new)` tries to persist `bypass_wizard_check` through `Wizard#requires_completion?`; PG rejects the INSERT in a read-only savepoint. The failure/stack is retained, and actual safe field getters are compared separately without stubbing or allowing the write. | An independently appropriate read-only upstream wizard path, or a read-only-safe aggregate oracle. No DB reset/warm writes. |
| `reference/native_site.rb` | Complete client-settings registry | 390 source-core non-themeable client fields only; 375 additional plugin/computed/themeable fields omitted on this site. Full catalog parity remains false in the report. Nonempty uploaded-image lists, plugin-owned upcoming-change dependencies and broader setting-type/custom policy cases remain unextracted; English/login-required guards remain. | Extract computed helpers and theme/plugin settings from source, preserve client-safe filtering/type behavior, test changed configurations. |
| `lib/preloads.rb` | Theme/custom HTML/upcoming per-user hooks | `themeSiteSettingOverrides`, `customHTML`, `activatedThemes` and per-user `upcomingChanges` are explicit empty objects, not evaluations of theme/plugin builders. Source-default promotion is separately handled in settings. Nonempty custom emoji fails closed rather than inventing assets. | Real theme selection/settings/HTML builders, anonymous upcoming-group logic and custom emoji/upload ACLs. |
| `frontend/stage-assets.py` | Locale scope | Core English YAML and source moment formatter adaptation. Compiled MessageFormat bundle is not extracted: `messageFormatData` currently returns an explicitly empty bundle. Plugin/theme/override translations are omitted. | Stage actual MessageFormat compiler output and additional locale/override/plugin sources. |
| `frontend/stage-assets.py` | CSS and asset build provenance | Core common CSS is byte-hashed existing reference compiler output, not independently rebuilt from raw Sass. No Horizon CSS is attached to Foundation. Theme/plugin asset bundles and changing theme/site settings are not automatically restaged in the running process. | Reproducible isolated common/plugin/theme build and dynamic asset invalidation/selection. Stage descriptor records actual inputs/outputs and any palette/font compilation. |
| `frontend/native_document.rb` | Layout and setup | Anonymous source-adapted layout, not a Rails ERB engine. No authentication/CSRF/session, analytics, theme/plugin HTML or full noscript document. Trusted `MINIMAL_ORIGIN` is needed for canonical absolute URLs behind the existing proxy (which forwards Host localhost). | Extract only required layout surfaces with separate security and browser tests. |
| `frontend/native_document.rb` | Core service worker | Actual source worker is served with native prefix/origin substitution; Rails-registered plugin worker hooks are deliberately omitted. Push subscription/share-target backend routes are not implemented. | Plugin worker assets and corresponding authenticated APIs; registering a core worker is not push-feature coverage. |
| `lib/avatars.rb`, `tools/stage-media.py` | Public uploaded avatars | Live username/current-upload/secure checks; existing optimized images preferred, otherwise actual original image bytes without resize writes. Historical/associated-account avatar lookup and runtime media restaging are not implemented. Missing/ineligible images use the actual stock blank asset. | Native resize/cache adapter, broader avatar membership and secure-upload behavior; dynamic media availability. |
| `lib/avatars.rb` | External letter-avatar proxy | Task forbids external HTTP. Uses the real Rails `render_blank` asset (offline divergence), not generated letter identities or a CDN proxy. | Local source-correct letter-avatar image generation; no external network dependency. |
| `lib/message_bus.rb` | Complete MessageBus transport | Synchronous short polling for observed guest latest channels only; no long-poll/hijack/chunking, publish, authenticated identity, arbitrary/plugin channels or subscriptions/listeners. | Additional channels/filters and transport semantics only as required, with ACL regression tests. |
| `lib/latest.rb` | Full query options | Explicit SQL translation, anonymous default ordering/page only. No arbitrary category/tag/search/sort/custom field filters. | Extract options and guardian/plugin behavior with parity tests. |
| `lib/latest.rb`, `lib/serializers.rb` | Tags/images/featured links/title generation | Nonempty tags, topic images/thumbnails, uncached fancy titles or featured links fail closed. Unsupported localization/nested/mute-all/default avatar/custom-small-logo/emoji-deny/plain-title/solved-empty-box settings remain guarded. | Source-correct serializer/upload/title/tag policy, no DB-writing jobs. |
| `lib/users.rb` | Avatar normalization/flair | Non-ASCII usernames, flair image uploads and unsupported external-avatar configurations remain guarded. Task hostname localhost; client applies mount prefix to serialized root-relative avatar URLs. | Native Unicode/CDN/deployment/flair adapters. |
| `lib/latest.rb`, `PLUGIN_SUPPORT.json` | Full plugin/authentication support | Selected Solved/topic-voting list attributes and source navigation constants only. No complete plugin boot/hooks/events/routes/frontend bundles or theme behavior. Cookies do not authenticate; mutations rejected. | Explicit per-plugin/authenticated extraction and tests. Core Ember boot is not plugin coverage. |
| `bin/discourse.rb` | Production server | Small sequential loopback connection-close adapter; one PG connection, no production Rack/session/websocket/concurrency/rate-limiting/recovery. Only GET plus bounded read-only MessageBus POST. | Production HTTP/runtime hardening if this extraction grows beyond local proof. |
| `bin/discourse.rb` | Topic page / other routes | `/t/...` and `/t/...json`, `/site` APIs, login/search/category/plugin/mutation routes remain 404/405. A correct topic link is **not** topic content. | Topic page/API extraction is next M3, not part of this ticket. |

Oracle runners are verification/build tooling only and exit synchronously. No Ruby
or Rails subprocess serves native data/documents/static requests. Ignored `build/`
contains generated binaries/assets/screenshots/logs and verification-only captures.
