.PHONY: verify verify-topic-query verify-settings-pure verify-plugin-pure
verify:
	python3 tools/verify.py

# Intentionally nonzero until the original native security closure is proven.
verify-topic-query:
	python3 tools/verify_topic_query.py

# Pure dependency proof only. Never substitutes for either acceptance target.
verify-settings-pure:
	python3 tools/verify_settings_pure.py

# Actual unconfigured plugin predicate + original in-memory modifier dispatch.
verify-plugin-pure:
	python3 tools/verify_plugin_pure.py

# Positive, explicitly partial milestone. Never accepts broader019 or /latest.
.PHONY: verify-anonymous-security
verify-anonymous-security:
	python3 tools/verify_anonymous_security.py

# Measured complete query/list input + separate initializer/API prefix.
# Deliberately nonzero until original boot/query proof is actually complete.
.PHONY: probe-original-query
probe-original-query:
	python3 tools/probe_original_query.py --initializer

# Observe actual original Rails activation, configuration and captured callback
# order, plus strict/full-query/constructor reapplication. Deliberately FAILING
# while native activation or full original query remains unsupported.
.PHONY: probe-plugin-activation
probe-plugin-activation:
	python3 tools/probe_original_query.py --initializer --activation-trace

# Real original source metadata construction only; never script activation/019.
.PHONY: verify-plugin-metadata
verify-plugin-metadata:
	python3 tools/verify_plugin_metadata.py

# Complete genuine registry205 dependency, not native plugin activation.
.PHONY: verify-archetype-dependency probe-remaining-activation
verify-archetype-dependency:
	python3 tools/verify_archetype_dependency.py

# Reapply remaining source debt without repeating completed memo-reader proof.
# Still intentionally nonzero while real activation/query parity is missing.
probe-remaining-activation:
	python3 tools/probe_original_query.py --initializer --activation-trace --no-reader-recheck

# Genuine live frontend graph/files dependency only; never HTML/page acceptance.
.PHONY: verify-ember-asset-graph
verify-ember-asset-graph:
	python3 -m unittest discover -s test -p test_ember_asset_graph.py

# Isolated original helper methods + explicit unit context, not an HTML request.
.PHONY: verify-asset-preloads
verify-asset-preloads:
	python3 -m unittest discover -s test -p test_asset_preloads.py

# Genuine random nonce/provider/injector dependency with labelled unit policies.
.PHONY: verify-csp-nonce
verify-csp-nonce:
	python3 -m unittest discover -s test -p test_csp_nonce.py

# Exact source string escaping with standalone JSON unit preloader, not Site JSON.
.PHONY: verify-layout-preload-json
verify-layout-preload-json:
	python3 -m unittest discover -s test -p test_layout_preload_json.py

# Actual Propshaft file-backed URL resolution, explicit unit config only.
.PHONY: verify-asset-urls
verify-asset-urls:
	python3 -m unittest discover -s test -p test_asset_urls.py

# Concrete pinned ERB span only; real resolver + source helpers, not a page.
.PHONY: verify-application-asset-fragment
verify-application-asset-fragment:
	python3 -m unittest discover -s test -p test_application_asset_fragment.py

# Actual read-only Propshaft Rack method component, no listener or page.
.PHONY: verify-asset-response
verify-asset-response:
	python3 -m unittest discover -s test -p test_asset_response.py

# Original Default/Builder plus actual ActionDispatch serialization; UNIT inputs only.
.PHONY: verify-csp-policy
verify-csp-policy:
	python3 -m unittest discover -s test -p test_csp_policy.py

# Real HTML request/controller/query prefix with refusal BEFORE rendering/Site.
# No original Rails HTML reference invocation; never HTML200/page acceptance.
.PHONY: verify-html-request-stage
verify-html-request-stage:
	python3 tools/probe_latest_html_stage.py

# Genuine body-before-layout source prefix; refuses category cache capability.
# No completed list body, layout, HTML200 or page acceptance.
.PHONY: verify-list-template-prefix
verify-list-template-prefix:
	python3 tools/probe_list_template_stage.py

# Real owned Category#url cache acquisition on genuine HTML controller state.
# Native/shared/raw-original methods plus async/namespace/error controls; NOT body/page.
.PHONY: verify-category-url-cache
verify-category-url-cache:
	python3 tools/probe_category_cache_stage.py

# Complete actual list/list body and captured RSS/metadata head with owned cache.
# Refuses before layout helpers; NEVER a complete layout, HTML response or page.
.PHONY: verify-list-body-head
verify-list-body-head:
	python3 tools/probe_list_body_stage.py

# Actual layout header + complete layouts/head after the real body; import-map
# acquisition still refuses. Never a complete layout, HTML200 or page.
.PHONY: verify-list-layout-head
verify-list-layout-head:
	python3 tools/probe_list_layout_stage.py

# Source-owned actual import-map prefix; retained real V8 + compiler String cache.
# Still refuses Theme array/bake acquisition. NEVER complete HTML/page acceptance.
.PHONY: verify-importmap-compiler-prefix
verify-importmap-compiler-prefix:
	python3 tools/probe_importmap_compiler_stage.py

# Independent Ruby-free original MiniRacer component, NOT a request or page.
.PHONY: verify-layout-vm-component
verify-layout-vm-component:
	BUNDLE_GEMFILE=../discourse/Gemfile bundle exec ruby tools/probe_layout_asset_processor_native.rb

# Actual source-owned Theme extra_js Array/Marshal cache; no bake PG writes.
# Remaining import-map graph still refuses; NEVER complete HTML/page acceptance.
.PHONY: verify-theme-array-cache
verify-theme-array-cache:
	python3 tools/probe_theme_array_stage.py

# Actual development EmberAssets filesystem/cache/error lifecycle differential.
# Unit mutation fixtures are distinct from genuine request inputs; NOT a page.
.PHONY: verify-request-ember-lifecycle
verify-request-ember-lifecycle:
	python3 tools/probe_request_ember_lifecycle.py

# Genuine source-built serving-root capability + full returned import-map partial.
# Readonly Propshaft resolution; no live build/watch/HTML200/browser acceptance.
.PHONY: verify-importmap-assets
verify-importmap-assets:
	python3 tools/probe_importmap_assets_stage.py

# Genuine YAML/plugin locale reads + original JS output, unit component only.
# Exact original/shared/native bytes and required-MF-removal mutation control.
.PHONY: verify-client-locale-component
verify-client-locale-component:
	python3 tools/probe_client_locale_source.py

# Actual main locale JS/digest/shared-cache/preload on cumulative native layout.
# Refuses next unacquired MF compiler; not HTML200/browser/page acceptance.
.PHONY: verify-layout-main-locale
verify-layout-main-locale:
	python3 tools/probe_locale_layout_stage.py

# Original MessageFormat VM component, explicit unit inputs only; NOT a page.
.PHONY: verify-messageformat-vm
verify-messageformat-vm:
	python3 tools/probe_messageformat_vm.py

# Actual YAML/readonly override -> original native MF compiler -> locale preload.
# Next client-override bundle still refuses; no full HTML/browser acceptance.
.PHONY: verify-layout-messageformat
verify-layout-messageformat:
	python3 tools/probe_messageformat_stage.py

# Explicit synthetic override formatting/fallback/slice identity UNIT differential.
# Never supplies live application overrides or accepts a page.
.PHONY: verify-client-overrides-unit
verify-client-overrides-unit:
	python3 tools/probe_client_overrides_unit.py

# Actual readonly override query/helper + original present nil-cache entry.
# Refuses next Theme translation bulk cache; NOT HTML200/browser/page.
.PHONY: verify-layout-client-overrides
verify-layout-client-overrides:
	python3 tools/probe_client_overrides_stage.py

# Genuine async source bulk lifecycle with explicit UNIT-only tuple producers.
# Present nil, frozen misses, ordering, real publication and guarded negatives.
.PHONY: verify-theme-bulk-lifecycle
verify-theme-bulk-lifecycle:
	python3 tools/probe_theme_bulk_lifecycle.py

# Genuine readonly Theme lookup/field query/callback + original typed bulk cache.
# Stops at browser-detect preload; never full layout/HTML200/browser acceptance.
.PHONY: verify-layout-theme-lookup
verify-layout-theme-lookup:
	python3 tools/probe_theme_lookup_stage.py

# Actual source browser-detect + acquired module preload graph, not a page.
# Next Theme head_tag helper still refuses.
.PHONY: verify-layout-core-preloads
verify-layout-core-preloads:
	python3 tools/probe_core_preload_stage.py

# Source common/desktop head_tag relation/or and actual two-key nil bulk effects.
# Next analytics helper refuses; not a complete layout or page.
.PHONY: verify-layout-head-tag
verify-layout-head-tag:
	python3 tools/probe_head_tag_stage.py

# Actual head analytics/manifest/iOS decisions, stops inside source yield(:head).
.PHONY: verify-layout-head-configuration
verify-layout-head-configuration:
	python3 tools/probe_head_configuration_stage.py

# Source layout_for yields genuine captured head; raw-read/fresh-safe-copy identity.
# Next markdown helper refuses; not full layout/HTML200/browser acceptance.
.PHONY: verify-layout-head-yield
verify-layout-head-yield:
	python3 tools/probe_head_yield_stage.py

# Real upcoming getter, markdown path/query/tag and plugin head helper.
# Source-built head only; next client setup builder refuses.
.PHONY: verify-layout-markdown-link
verify-layout-markdown-link:
	python3 tools/probe_markdown_link_stage.py

# Actual lazy builder owner/identity and original client setup read prefix.
# Refuses before unacquired asset-version graph/MessageBus effects.
.PHONY: verify-layout-client-setup-prefix
verify-layout-client-setup-prefix:
	python3 tools/probe_client_setup_prefix_stage.py

# Actual full serving load_path/digested-path/MD5 graph before MessageBus effects.
.PHONY: verify-layout-asset-version-graph
verify-layout-asset-version-graph:
	python3 tools/probe_asset_version_graph_stage.py

# Existing owned fixture: original global last-message and conditional publication.
.PHONY: verify-layout-asset-version-bus verify-asset-version-bus-unit
verify-layout-asset-version-bus:
	python3 tools/probe_asset_version_bus_stage.py
verify-asset-version-bus-unit:
	python3 tools/probe_asset_version_bus_unit.py

# Actual controller classification and source HighlightJs files/version/path.
.PHONY: verify-layout-client-highlight
verify-layout-client-highlight:
	python3 tools/probe_client_highlight_stage.py

# Source-order SVG cache prefix, separately measured actual readonly icon producers.
.PHONY: verify-layout-svg-cache verify-svg-icons-unit
verify-layout-svg-cache:
	python3 tools/probe_svg_cache_stage.py
verify-svg-icons-unit:
	python3 tools/probe_svg_icons_unit.py

# Actual ordered settings_hash consumer getters; not full settings declaration boot.
.PHONY: verify-layout-svg-settings
verify-layout-svg-settings:
	python3 tools/probe_svg_settings_stage.py

# Source warn:false legacy aliases in settings_hash, not general warning support.
.PHONY: verify-layout-svg-legacy
verify-layout-svg-legacy:
	python3 tools/probe_svg_legacy_stage.py

# Reuse acquired upcoming/default top_menu getter, not the raw stored default.
.PHONY: verify-layout-svg-top-menu
verify-layout-svg-top-menu:
	python3 tools/probe_svg_top_menu_stage.py

# Exact source-pinned no-wrap enum getters; broader named/wrapped enums refuse.
.PHONY: verify-layout-svg-enums
verify-layout-svg-enums:
	python3 tools/probe_svg_enum_stage.py

# Exact source upcoming-default target getters, not permission-map expansion.
.PHONY: verify-layout-svg-defaults
verify-layout-svg-defaults:
	python3 tools/probe_svg_default_stage.py

# Actual upcoming code-login change with real ordered dependencies.
.PHONY: verify-layout-svg-local-login
verify-layout-svg-local-login:
	python3 tools/probe_svg_local_login_stage.py

# Explicit additional FullNameRequirement enum scope; previous scopes unchanged.
.PHONY: verify-layout-svg-full-name
verify-layout-svg-full-name:
	python3 tools/probe_svg_full_name_stage.py

# Upcoming remove/replace GETTER only; never toggle/action/migration.
.PHONY: verify-layout-svg-uncategorized
verify-layout-svg-uncategorized:
	python3 tools/probe_svg_uncategorized_stage.py

# Shared immediate wrap(...).to_s composition, NOT generic native wrapped getter.
.PHONY: verify-layout-svg-wrapped-consumer
verify-layout-svg-wrapped-consumer:
	python3 tools/probe_svg_wrapped_stage.py

# Exact Emoji/String and notice TrustLevel/Integer enum getter return contracts.
.PHONY: verify-layout-svg-notice-enums
verify-layout-svg-notice-enums:
	python3 tools/probe_svg_notice_enums_stage.py

# Explicit list enum is choices metadata, not a wrapped enum getter.
.PHONY: verify-layout-svg-choice-list
verify-layout-svg-choice-list:
	python3 tools/probe_svg_choice_list_stage.py

# Source AST distinguishes nested helpers from top-level generated getter names.
.PHONY: verify-layout-svg-lexical-getters
verify-layout-svg-lexical-getters:
	python3 tools/probe_svg_nested_stage.py

# Values/type metadata only, no S3 transport/helper/action acquisition.
.PHONY: verify-layout-svg-media-enums
verify-layout-svg-media-enums:
	python3 tools/probe_svg_media_enums_stage.py

# Actual uploaded-image-list empty branch; no fabricated empty cache hit.
.PHONY: verify-layout-svg-uploaded-list
verify-layout-svg-uploaded-list:
	python3 tools/probe_svg_uploaded_list_stage.py

# Actual core media-convert feature GETTER only, no conversion worker/action.
.PHONY: verify-layout-svg-media-convert
verify-layout-svg-media-convert:
	python3 tools/probe_svg_media_convert_stage.py

# Actual inherited Onebox locale read/no-wrap/lock contract, no UI/network.
.PHONY: verify-layout-svg-onebox
verify-layout-svg-onebox:
	python3 tools/probe_svg_onebox_stage.py

# Actual Reviewable enum reads only; no moderation/UI actions.
.PHONY: verify-layout-svg-review-enums
verify-layout-svg-review-enums:
	python3 tools/probe_svg_review_enums_stage.py

# Actual utility enum getter values, not associated UI/actions.
.PHONY: verify-layout-svg-utility-enums
verify-layout-svg-utility-enums:
	python3 tools/probe_svg_utility_enums_stage.py

# Actual default-preference enum read values, no preference actions/UI activation.
.PHONY: verify-layout-svg-preference-enums
verify-layout-svg-preference-enums:
	python3 tools/probe_svg_preference_enums_stage.py

# Source experimental Boolean getters only; no flag setters or feature actions.
.PHONY: verify-layout-svg-experimental
verify-layout-svg-experimental:
	python3 tools/probe_svg_experimental_stage.py

# Full source settings_hash consumer return, actual objects current identity.
.PHONY: verify-layout-svg-settings-snapshot
verify-layout-svg-settings-snapshot:
	python3 tools/probe_svg_objects_stage.py

# Real SVG settings/plugin/badge/group icon producers and owned publication/hits.
.PHONY: verify-layout-svg-icon-producers
verify-layout-svg-icon-producers:
	python3 tools/probe_svg_icon_producers_stage.py

# Actual Theme settings and SVG modifier read/cache branches, no setting writes.
.PHONY: verify-layout-svg-theme-icons
verify-layout-svg-theme-icons:
	python3 tools/probe_svg_theme_icons_stage.py

# Stateless native XML DOM component vs complete raw Nokogiri source assets.
.PHONY: verify-svg-xml-engine
verify-svg-xml-engine:
	bundle exec ruby tools/probe_svg_xml_engine.rb

# Actual complete XML bundle/digest/path, explicitly bounded native -O0 profile.
.PHONY: verify-layout-svg-bundle
verify-layout-svg-bundle:
	python3 tools/probe_svg_bundle_stage.py

# Actual full setup meta immediate consumer; environment/Hash object API not claimed.
.PHONY: verify-layout-client-meta
verify-layout-client-meta:
	python3 tools/probe_client_meta_stage.py

# Actual config/auth/body/complete splash; refuses stylesheet effects, not a page.
.PHONY: verify-layout-body-splash
verify-layout-body-splash:
	python3 tools/probe_body_layout_stage.py

# Actual manager constructor/memo/arguments only, not stylesheet cache/URL/build.
.PHONY: verify-layout-stylesheet-manager-read
verify-layout-stylesheet-manager-read:
	python3 tools/probe_stylesheet_manager_read_stage.py
