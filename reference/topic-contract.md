# Minimal anonymous topic projection (`minimal-topic-v1`)

This reference-only oracle compares fresh, native topic JSON with source-derived values. It is not a Rails HTTP response capture and is never runtime data. The runner builds actual `TopicView`, `TopicViewSerializer`, `TopicViewDetailsSerializer`, `PostSerializer`, and `BasicUserSerializer` objects under one PostgreSQL `READ ONLY` transaction. It starts no server and sends no HTTP request. TopicView's message-bus read uses only the task Valkey configured in the environment.

From the Discourse checkout, after sourcing the task environment:

```sh
source ../harness/env.sh
DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development' \
  TOPIC_ORACLE_IDS=15 TOPIC_ORACLE_POST_NUMBER=1 \
  bin/rails runner ../minimal/reference/capture-topic-rails.rb \
  > ../minimal/build/topic-rails.json
python3 ../minimal/reference/compare-topic.py \
  --expected ../minimal/build/topic-rails.json \
  --candidate ../minimal/build/topic-native.json
```

Without `TOPIC_ORACLE_IDS`, the oracle selects three source-eligible anonymous regular topics by `bumped_at DESC, id DESC`; `TOPIC_ORACLE_COUNT` changes the sample size. `TOPIC_ORACLE_IDS` accepts a comma-separated list of positive actual IDs and preserves requested order; all IDs must pass the same eligibility and Guardian checks. Eligibility is non-deleted, non-private, non-shared-draft, existing public-category (including the actual Uncategorized category, not a NULL/missing category), excluding category-definition topics. It does not require `visible=true`: source direct-topic authorization uses `Guardian#can_see?`, and an unlisted topic can be visible by direct ID. `TOPIC_ORACLE_POST_NUMBER` selects the source near-post window (`1` is the first page; higher values invoke `TopicView#filter_posts_near`); request metadata records the selected number. The report also carries `topics_checked_by_guardian` and the complete, sorted `guardian_inaccessible_topic_ids` audit produced by calling actual anonymous `Guardian#can_see?` on every `Topic.unscoped` row (with category preloading) inside the same read-only transaction. These are IDs only, never private topic content, and support direct-route denial tests.


## Compared response shape and source provenance

The capture envelope is `contract`, `source_revision`, `selection`, `topics`, `read_only`. Each `topics[]` entry contains `request`, `topic`, `details`, and `post_stream`. `topic` contains values obtained from `TopicViewSerializer` getters or the specifically documented source direct getter below. `details` contains actual `TopicViewDetailsSerializer` getters plus BasicUserSerializer output. `post_stream.stream` uses `TopicView#filtered_post_ids` exact order, and `post_stream.posts` uses actual `TopicView#posts` order and window.

The current native `topic` key set is:

```
id title fancy_title posts_count created_at views reply_count like_count last_posted_at visible
closed archived has_summary archetype slug category_id word_count deleted_at user_id pinned_globally
pinned_at pinned_until slow_mode_seconds highest_post_number current_post_number chunk_size draft draft_key
draft_sequence unpinned pinned bookmarked
```

`fancy_title` is `Topic#fancy_title`: this pinned source has no `TopicViewSerializer#fancy_title` getter. `highest_post_number` and `current_post_number` come from TopicViewSerializer's corresponding getters (`TopicView#highest_post_number` is computed from filtered posts); `chunk_size` comes from TopicView and is 20. The `current_post_number` key is emitted only when `TopicViewSerializer#include_current_post_number?` is true. `visibility_reason_id` is present only when the actual `include_visibility_reason_id?` is true; `featured_link` only when `include_featured_link?` is true; `unicode_title` only when `include_unicode_title?` is true. Their values come from the respective serializer getters. These source conditionals are preserved, not replaced by unconditional nil or false values.

`details` has the four current native keys `can_edit`, `notification_level`, `created_by`, `last_poster`. The first two use actual TopicViewDetailsSerializer getters; user objects are serialized with actual BasicUserSerializer. This is a deliberate limited details projection, not a claim of the full Details serializer.

Every current native post includes the keys below, except the conditional fields listed afterward:

```
id username avatar_template created_at cooked post_number post_type posts_count updated_at reply_count
reply_to_post_number quote_count incoming_link_count reads readers_count score topic_id topic_slug
primary_group_name display_username user_id version yours can_edit can_delete can_recover
can_see_hidden_post can_wiki read action_code admin moderator staff trust_level hidden user_deleted wiki deleted_at
```

`primary_group_name` is the actual `PostSerializer#primary_group_name` getter, backed by TopicView's group-name lookup. The remaining values are PostSerializer or BasicPostSerializer getters; JSON keys `admin`, `moderator`, `staff` map to source methods `admin?`, `moderator?`, `staff?`. `action_code` is emitted only when actual `PostSerializer#include_action_code?` is true, with value from `PostSerializer#action_code`; it is absent for nil/empty source values. `name` is emitted only when the actual BasicPostSerializer `include_name?` is true (`SiteSetting.enable_names?`). `cooked_hidden` is emitted only when `include_cooked_hidden?` is true; its `cooked` value is the source placeholder for anonymously hidden posts, and raw content is never projected. `locked` is intentionally omitted: though `PostSerializer#locked` returns true, `include_locked?` is false for anonymous users unless the post is locked and is theirs or the viewer is staff, so native does not emit it.

This is an explicit source-verified projection, not whole-serializer parity. The comparator compares **all** candidate topic, details, post-stream, post, and nested user keys, including their exact key sets; any emitted key with no oracle counterpart is a failure, not silently discarded. It compares values and arrays without timestamp/HTML/string/value normalization. Fields not emitted by native (including the full topic actions/details, suggestions/related data, categories/tags, gaps/timeline/badges, post actions/edit history/raw/localizations, plugin/theme additions, and `locked`) are outside the native contract, not claimed as implemented. The oracle and docs must be extended with a corresponding source getter before native begins emitting another key.

A candidate may be the direct `/t/<slug>/<id>.json` JSON body or a file containing `{topics:[...]}`. Pass a specific file or directory; directories prefer `topic-native.json`, otherwise use `topic-*.json`. Directories allow one file per native topic without consuming latest/site evidence. Candidate topic IDs must exactly equal the capture's topic ID set; capture with `TOPIC_ORACLE_IDS` for one native document or the full ID set for a directory. A partial candidate cannot pass by overlapping only part of the oracle sample.
## Mounted-prefix cooked URL caveat

The native root `/t/...json` contract compares persisted cooked bytes to actual Rails `PostSerializer#cooked` output exactly, including `src`, `href`, and poster attributes. At a configured mount prefix, native `NativePaths#mount_topic` relocates only eligible local-root cooked URL attributes to the prefix for browser use. This mount-only rewritten cooked value is intentionally **not** claimed byte-equal to the root Rails getter. It must not rewrite external, protocol-relative, or fragment-only values. The source role is PrettyText's root `PrettyText.paths[:baseUri]`: cooked HTML is persisted/cooked in a root-relative context; the mounted helper is a serving-time path adaptation. No rebake or DB write is performed. The offline contract comparator is for the root native topic JSON; a mounted response's local-URL rewrite is a documented transport divergence.

## Exact unimplemented registered fields at the pinned source

The fresh oracle computes this inventory from each actual serializer class’s
registered attributes/associations (including installed plugin extensions),
subtracting the declared supported projection. A registered conditional field
is not necessarily present in an anonymous response. These are **not** evaluated,
implemented, or counted as matched merely because they are registered. `fancy_title`
is supported via the explicitly documented direct Topic getter.

### TopicViewSerializer: 88 unimplemented registered fields

```text
accepted_answers actions_summary ai_agent_id ai_agent_name ai_llm_model_id ai_search_cited_topics ai_search_conversation ai_summary ai_summary_record answer_count assigned_to_group assigned_to_user assignment_note assignment_status board_memberships bookmarks can_assign can_create_shared_issue can_localize_topic can_vote categories chat_channel_id deleted_by destination_category_id discourse_post_event_first_post_event discourse_zendesk_plugin_zendesk_id discourse_zendesk_plugin_zendesk_url event_all_day event_ends_at event_show_local_time event_starts_at event_timezone event_watching_invitee_status expandable_first_post external_id fancy_title_localized featured_link_root_domain has_accepted_answer has_cached_summary has_deleted has_livestream has_localized_content image_url indirectly_assigned_to is_bot_pm is_nested_view is_post_voting is_shared_draft is_template is_warning last_answer_post_number last_answered_at last_answerer last_commented_on last_read_post_id last_read_post_number livestream_chat_active locale message_archived message_bus_last_id participant_count pending_posts pm_with_non_human_user posted published_page queued_posts_count related_messages related_topics requested_group_name shared_issue_count shared_issue_visible show_read_indicator slow_mode_enabled_until suggested_group_name suggested_topics summarizable tags tags_descriptions tags_disable_ads thumbnails timeline_lookup topic_timer user_badges user_created_shared_issue user_last_posted_at user_voted valid_reactions vote_count
```

### TopicViewDetailsSerializer: 28 unimplemented registered fields

```text
allowed_groups allowed_users can_archive_topic can_banner_topic can_close_topic can_convert_topic can_create_post can_delete can_edit_staff_notes can_edit_tags can_flag_topic can_invite_to can_invite_via_email can_moderate_category can_move_posts can_permanently_delete can_pin_unpin_topic can_publish_page can_recover can_remove_allowed_users can_remove_self_id can_reply_as_new_topic can_review_topic can_split_merge_topic can_toggle_topic_visibility links notifications_reason_id participants
```

### PostSerializer: 95 unimplemented registered fields

```text
accepted_answer action_code_path action_code_who actions_summary ai_agent_id ai_agent_name ai_llm_model_id assigned_to_group assigned_to_user assignment_note assignment_status badges_granted bookmark_auto_delete_preference bookmark_id bookmark_name bookmark_reminder_at bookmarked calendar_details can_accept_answer can_assign can_localize_post can_permanently_delete can_unaccept_answer can_view_edit_history can_vote category_id comments comments_count current_user_reaction current_user_used_main_reaction deleted_by draft_sequence edit_reason event event_onebox_occurrences event_oneboxes excerpt flair_bg_color flair_color flair_group_id flair_name flair_url group_moderator group_timezones hidden_reason_id is_auto_generated is_localized language last_wiki_edit link_counts llm_name locale localization_outdated localized_oneboxes locked mentioned_users notice notice_created_by_user policy_accepted policy_accepted_by policy_accepted_by_count policy_can_accept policy_can_revoke policy_not_accepted_by policy_not_accepted_by_count policy_revoked policy_stats polls polls_votes post_localizations_count post_url post_voting_has_votes post_voting_user_voted_direction post_voting_vote_count raw reaction_users_count reactions reply_to_user reviewable_id reviewable_score_count reviewable_score_pending_count static_doc title_is_group topic_accepted_answer topic_html_title topic_title truncated user_birthdate user_cakedate user_custom_fields user_locale user_status user_suspended user_title via_email
```
