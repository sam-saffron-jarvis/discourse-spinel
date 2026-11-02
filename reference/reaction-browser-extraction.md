# Reactions browser extraction and compiled stage contract

Pinned source checkout: `../discourse` revision
`96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. Original source copies and SHA-256
provenance are listed in `reference/reactions-browser-sources/manifest.json` and
in the generated `build/assets/reactions-core/manifest.json`.

`frontend/stage-reactions.py` invokes the actual Discourse
`Plugin::JsCompiler` → `AssetProcessor#rollup` path. It publishes
`build/assets/reactions-core/js/...` and a top-level manifest with the requested
shape:

- `javascript.entrypoint`: `js/<compiled-entry>.js`, relative to the stage;
- `javascript.chunks`: relative JS paths, imports and SHA-256s;
- `javascript.files`: relative JS paths and SHA-256s;
- `javascript.source_files`: exact source module paths and SHA-256s.

The runtime core is unchanged `build/assets/discourse/`. Parent serves plugin
files under `/assets/reactions-core/` and emits the entry as a modulepreload with
`data-plugin-name="discourse-reactions"`. Discourse's existing
`loadPluginFromModulePreload` imports `compatModules`, defines the plugin's
module registry, and subsequently runs its initializer with the plugin
container. There is no core initializer stub, custom UI drawing, or runtime JS
injection.

The Rollup tree is deliberately limited to eight upstream originals: counter,
list, list-emoji, users-menu, action-summary, emoji helper, custom-reaction model,
and hidden-post helper. The only other modules are the named counter-only
`Actions` caller adapter and initializer adapter. The source model remains
byte-identical; its `fetchReactionsUsersList` method is the users menu's read
path. The initializer adapter runs only when
`discourse_reactions_enabled` is true, registers the actual `post-menu-buttons`
transformer, deletes native `LIKE`, adds original `ReactionsActionSummary`
before `REPLIES`, and registers the original tracked post fields:
`current_user_used_main_reaction`, `reaction_users_count`,
`current_user_reaction`, and `reactions`. The summary's `Actions` caller adapter
renders only the actual upstream counter at the left position. Its omission of
all action wrapper/touch/picker code is an explicit bounded caller adapter recorded
in `GAPS.md`, not a claim that the full Actions component initializes. Upstream action,
picker, nav, notification, and other plugin route modules are not fed to the
bundle or activated.

## Runtime dependencies

Required plugin settings:

- `discourse_reactions_enabled` (initializer gate);
- `discourse_reactions_enabled_reactions`;
- `discourse_reactions_reaction_for_like`;
- `discourse_reactions_like_icon`;
- `discourse_reactions_desaturated_reaction_panel`.

Required core settings are `enable_emoji` and
`prioritize_username_in_ux`. Parent owns the client catalog and native runtime
values. Plugin locale source is
`plugins/discourse-reactions/config/locales/client.en.yml`; parent merges it into
the existing locale output, and the stage manifest records its hash.

## CSS and isolated build behavior

The actual common, desktop and mobile plugin stylesheets are compiled through
`Stylesheet::Compiler.compile_asset` for `discourse-reactions`,
`discourse-reactions_desktop` and `discourse-reactions_mobile`, concatenated to
`build/assets/reactions-core/stylesheets/discourse-reactions.css`. The upstream
responsive files already scope their rules under `.desktop-view`/`.mobile-view`,
including the phone counter margin; no replacement CSS is invented. The manifest
records output hash, exact AssetProcessor digest/hash, and `source_files` hashes
relative to the Discourse checkout. Compilation verifies task PostgreSQL
127.0.0.1:5499 and Valkey 127.0.0.1:6399, uses a read-only Rails DB transaction,
and refuses to build/rewrite an absent or stale AssetProcessor cache. It does
not invoke asset precompile or write into `../discourse`. Parent copies CSS as
`native/css/discourse-reactions.css`.

Default `python3 frontend/stage-reactions.py` reuses the stage only after checking
all source, adapter, compiled JS, CSS, and AssetProcessor cache hashes. A changed
source requires explicit `--regenerate`. The build output takes about five
seconds in the current environment. Parent owns static path/MIME wiring, paced
plugin modulepreloads, merged locale behavior, runtime settings, endpoint
semantics and browser proof. This is only the anonymous read-only counter/users
list slice; it does not enable reaction writes or claim full plugin parity.
