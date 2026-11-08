# frozen_string_literal: true
# Runnable anonymous latest_results; no TopicList/serializer closure prerequisite.
require "prism"
require "json"
require "digest"
root = File.expand_path("../..", __dir__)
source = File.binread(File.join(root, "fidelity/source/discourse/lib/topic_query.rb"))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
changes = []
method_for = lambda { |name| methods.find { |node| node.name == name } || raise("missing source method #{name}") }
replace = lambda do |method, node, replacement, reason|
  changes << {method: method.name, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice), replacement_sha256: Digest::SHA256.hexdigest(replacement), reason: reason}
  method.slice.dup.tap { |text| text[node.location.start_offset - method.location.start_offset, node.location.length] = replacement }
end
muted_topics = method_for.call(:remove_muted_topics)
user_branch = muted_topics.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice == "user" }
topics_source = replace.call(muted_topics, user_branch, "", "guarded anonymous identity: original nonnil per-user topic state is unsupported")
topics_source = topics_source.sub("def remove_muted_topics(list, user)", "def remove_muted_topics(list, user)\n    raise ArgumentError, \"unsupported authenticated muted-topic profile\" unless user.nil?")

muted_categories = method_for.call(:remove_muted_categories)
user_branch = muted_categories.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice == "user" }
raise "anonymous category-default branch changed" unless user_branch&.subsequent.is_a?(Prism::IfNode)
anonymous = user_branch.subsequent.slice.sub("elsif ", "if ")
categories_source = replace.call(muted_categories, user_branch, anonymous, "guarded anonymous identity; keep BOTH live mute-all/default-muted category branches")
categories_source = categories_source.sub("def remove_muted_categories(list, user, opts = nil)", "def remove_muted_categories(list, user, opts = nil)\n    raise ArgumentError, \"unsupported authenticated category-mute profile\" unless user.nil?")
categories_source = categories_source.sub("category_ids.exclude?(category_id)", "!category_ids.include?(category_id)")

muted_tags = method_for.call(:remove_muted_tags)
tags_source = muted_tags.slice.dup
tags_changes = []
muted_tags.body.body.grep(Prism::IfNode).each do |node|
  predicate = node.predicate.slice
  if predicate == "user.present?"
    tags_changes << [node, node.subsequent.statements.slice, "anonymous identity: preserve actual default_tags_muted lookup"]
  elsif predicate.include?("opts[:tags].present?")
    tags_changes << [node, "", "tags request key explicitly refused by supported default_results profile"]
  elsif predicate == "user && !opts[:skip_categories]"
    tags_changes << [node, "", "guarded anonymous identity: no per-user category notification override"]
  end
end
raise "muted tag branch set changed" unless tags_changes.length == 3
tags_changes.sort_by { |node, _, _| -node.location.start_offset }.each do |node, replacement, reason|
  tags_source[node.location.start_offset - muted_tags.location.start_offset, node.location.length] = replacement
  changes << {method: muted_tags.name, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice), replacement_sha256: Digest::SHA256.hexdigest(replacement), reason: reason}
end
tags_source = tags_source.sub("def self.remove_muted_tags(list, user, opts = {})", "def self.remove_muted_tags(list, user, opts = {})\n    raise ArgumentError, \"unsupported authenticated muted-tag profile\" unless user.nil?")
remove_muted = method_for.call(:remove_muted).slice.sub("TopicQuery.remove_muted_tags", "self.class.remove_muted_tags")
latest = method_for.call(:latest_results)
shared = method_for.call(:apply_shared_drafts)
# Shared drafts require the unproved special group-map API. Keep the actual
# source early return and explicitly refuse enabled profiles rather than omit
# their required behavior while reporting success.
early_return = shared.body.body.first
raise "shared drafts source guard changed" unless early_return.slice == 'return result if SiteSetting.shared_drafts_category == ""'
shared_source = "def apply_shared_drafts(result, category_id, options)\n    #{early_return.slice}\n    raise ArgumentError, \"unsupported shared-drafts profile\"\n  end"
changes << {method: shared.name, start_byte: shared.location.start_offset, end_byte: shared.location.end_offset,
  text_sha256: Digest::SHA256.hexdigest(shared.slice), replacement_sha256: Digest::SHA256.hexdigest(shared_source),
  reason: "enabled shared-drafts site profile explicitly refuses; original empty-setting early return retained"}
component = <<~RUBY
  # frozen_string_literal: true
  # Supported anonymous latest_results ONLY, not TopicList hydration or page.
  class TopicQueryLatestResults < TopicQueryDefaultResults
    def self.validate_options!(options, internal = false)
      super(options, internal)
      raise ArgumentError, "unsupported shared-drafts profile" unless SiteSetting.shared_drafts_category == ""
    end

    def self.results_filter_callbacks
      TopicQuery.results_filter_callbacks
    end

    def default_results(options = {})
      results(options)
    end

    #{latest.slice}

    #{remove_muted}

    #{topics_source}

    #{categories_source}

    #{tags_source}

    #{shared_source}
  end
RUBY
raise "invalid latest_results component" unless Prism.parse(component).success?
directory = File.join(root, "fidelity/progressive/stage3a")
Dir.mkdir(directory) unless Dir.exist?(directory)
File.binwrite(File.join(directory, "topic_query_latest_results.rb"), component)
selected = %i[latest_results remove_muted remove_muted_topics remove_muted_categories remove_muted_tags apply_shared_drafts].map { |name| method_for.call(name) }
manifest = {profile: "supported anonymous latest_results ONLY; no list hydration", baseline_revision: "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  source: "lib/topic_query.rb", source_sha256: Digest::SHA256.hexdigest(source),
  methods: selected.map { |node| {name: node.name, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  guarded_source_changes: changes, live_values_used_as_inputs: false,
  candidate_sha256: Digest::SHA256.hexdigest(component), unsupported_live_feature_profiles: %w[shared_drafts_category_nonempty],
  result_filter_registry: "actual TopicQuery cattr_accessor/init/source callback iteration, not an empty replacement",
  full_query_accepted: false, list_hydration_accepted: false, page_accepted: false}
File.write(File.join(directory, "MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
