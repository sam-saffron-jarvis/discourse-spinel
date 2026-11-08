# frozen_string_literal: true
# Source-backed list_latest + anonymous TopicList hydration. No hand-written
# topic backend or bare-model JSON serialization is introduced.
require "prism"
require "json"
require "digest"
root = File.expand_path("../..", __dir__)
reference = File.join(root, "fidelity/source/discourse")
directory = File.join(root, "fidelity/progressive/stage3b")
Dir.mkdir(directory) unless Dir.exist?(directory)
changes = []
def list_nodes(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| list_nodes(child, result) }
  result
end
query_source = File.binread(File.join(reference, "lib/topic_query.rb"))
query_owner = Prism.parse(query_source).value.statements.body.grep(Prism::ClassNode).first
query_methods = query_owner.body.body.grep(Prism::DefNode)
create = query_methods.find { |node| node.name == :create_list }
create_source = create.slice.dup
cut = list_nodes(create).grep(Prism::IfNode).select { |node| node.predicate.slice == "filter == :private_messages" || node.predicate.slice == "filter == :filter && options[:include_filter_option_info]" }
raise "list dispatch source branches changed" unless cut.length == 2
cut.sort_by { |node| -node.location.start_offset }.each do |node|
  replacement = node.predicate.slice == "filter == :private_messages" ? node.subsequent.statements.slice : ""
  create_source[node.location.start_offset - create.location.start_offset, node.location.length] = replacement
  changes << {source: "lib/topic_query.rb", method: "create_list", start_byte: node.location.start_offset,
    end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice),
    reason: "only :latest list dispatcher admitted; private-message/filter-info profiles explicitly refused"}
end
create_source = create_source.sub("def create_list(filter, options = {}, topics = nil)", "def create_list(filter, options = {}, topics = nil)\n    raise ArgumentError, \"unsupported list profile\" unless filter == :latest && @user.nil?")
list_latest = query_methods.find { |node| node.name == :list_latest }
pinning = query_methods.find { |node| node.name == :prioritize_pinned_topics }
query = <<~RUBY
  # frozen_string_literal: true
  # Supported anonymous :latest list dispatcher, including original pinning.
  class TopicQueryListLatest < TopicQueryLatestResults
    def self.validate_options!(options, internal = false)
      checked = options.dup
      if checked.key?(:filter)
        raise ArgumentError, "unsupported list filter" unless checked[:filter] == :latest || checked[:filter] == "latest"
        checked.delete(:filter)
      end
      super(checked, internal)
      raise ArgumentError, "unlimited list profile unsupported" if options[:limit] == false
      raise ArgumentError, "unsupported list locale" unless I18n.locale.to_s == "en"
    end

    #{list_latest.slice}

    #{create_source}

    #{pinning.slice}
  end
RUBY
query = query.gsub(/^[ \t]+$/, "")
raise "invalid list query" unless Prism.parse(query).success?
File.binwrite(File.join(directory, "topic_query_list_latest.rb"), query)

path = "app/models/topic_list.rb"
source = File.binread(File.join(reference, path))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
load = methods.find { |node| node.name == :load_topics }
load_source = load.slice.dup
edits = []
load.body.body.each do |node|
  if node.is_a?(Prism::IfNode) && node.predicate.slice == "@current_user"
    edits << [node, "", "anonymous constructor/profile guard excludes per-user notification/dismissed lookup"]
  elsif node.is_a?(Prism::LocalVariableWriteNode) && node.name == :post_action_type
    edits << [node, "post_action_type = nil", "original conditional is nil for the guarded anonymous identity"]
  elsif node.is_a?(Prism::IfNode) && node.predicate.slice == "post_action_type"
    edits << [node, "post_action_lookup = nil", "no authenticated post-action query in guarded anonymous profile"]
  end
end
# The remaining write to per-user post_action_data likewise belongs only to
# the excluded authenticated branch; all poster/user/group/preload code stays.
action = list_nodes(load).grep(Prism::IfNode).find { |node| node.predicate.slice.start_with?("ft.user_data && post_action_lookup") }
raise "per-user post-action source branch changed" unless action
edits << [action, "", "authenticated post-action data branch unavailable under anonymous profile guard"]
raise "anonymous list branch set changed" unless edits.length == 5
edits.sort_by { |node, _, _| -node.location.start_offset }.each do |node, replacement, reason|
  load_source[node.location.start_offset - load.location.start_offset, node.location.length] = replacement
  changes << {source: path, method: "load_topics", start_byte: node.location.start_offset,
    end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice), reason: reason}
end
field_guard = list_nodes(load).grep(Prism::CallNode).find { |node| node.name == :present? && node.receiver&.slice == "preloaded_custom_fields" }
raise "custom-field collection guard changed" unless field_guard
load_source = load_source.sub(field_guard.slice, "preloaded_custom_fields && !preloaded_custom_fields.empty?")
changes << {source: path, method: "load_topics custom field guard", start_byte: field_guard.location.start_offset,
  end_byte: field_guard.location.end_offset, text_sha256: Digest::SHA256.hexdigest(field_guard.slice),
  reason: "explicit nil/empty collection check: native Object#blank? does not dispatch Set#empty?"}
load_source = load_source.sub("def load_topics", "def load_topics\n    raise ArgumentError, \"unsupported authenticated list hydration\" unless @current_user.nil?")
initialize = methods.find { |node| node.name == :initialize }
initializer = initialize.slice.sub("def initialize(filter, current_user, topics, opts = nil)", "def initialize(filter, current_user, topics, opts = nil)\n    raise ArgumentError, \"unsupported list identity/filter\" unless current_user.nil? && filter == :latest")
lookup = methods.find { |node| node.name == :category_user_lookup }
lookup_source = "def category_user_lookup\n    raise ArgumentError, \"unsupported authenticated category lookup\" unless @current_user.nil?\n    @category_user_lookup ||= []\n  end"
changes << {source: path, method: "category_user_lookup", start_byte: lookup.location.start_offset,
  end_byte: lookup.location.end_offset, text_sha256: Digest::SHA256.hexdigest(lookup.slice),
  reason: "preserve original memoized anonymous [] branch; nonnil current_user explicitly refuses"}
names = %i[on_preload cancel_preload preload on_preload_user_ids preload_user_ids topics categories preload_key]
selected = owner.body.body.select do |node|
  node.is_a?(Prism::CallNode) && %i[include cattr_accessor preloaded_custom_fields= attr_accessor].include?(node.name)
end
accessor = selected.find { |node| node.name == :cattr_accessor }
raise "custom-field cattr source declaration changed" unless accessor&.arguments&.arguments&.first&.slice == ":preloaded_custom_fields"
changes << {source: path, method: "preloaded_custom_fields accessors", start_byte: accessor.location.start_offset,
  end_byte: accessor.location.end_offset, text_sha256: Digest::SHA256.hexdigest(accessor.slice),
  reason: "explicit instance forwarding to actual class accessor; common native cattr lowering supplies class API only"}
forwarding = "def preloaded_custom_fields\n    self.class.preloaded_custom_fields\n  end\n\n  def preloaded_custom_fields=(fields)\n    self.class.preloaded_custom_fields = fields\n  end"
parts = selected.map(&:slice) + [forwarding] + methods.select { |node| names.include?(node.name) }.map(&:slice) + [initializer, load_source]
list = "# frozen_string_literal: true\n# Supported anonymous TopicList read/hydration API, not serializable_hash.\nclass TopicList\n" + parts.map { |text| "  " + text }.join("\n\n") + "\n\n  private\n  " + lookup_source + "\nend\n"
list = list.gsub(/^[ \t]+$/, "")
raise "invalid supported TopicList" unless Prism.parse(list).success?
File.binwrite(File.join(directory, "topic_list.rb"), list)
manifest = {profile: "supported anonymous list_latest + TopicList.topics hydration ONLY", baseline_revision: "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  source_sha256: {"lib/topic_query.rb" => Digest::SHA256.hexdigest(query_source), path => Digest::SHA256.hexdigest(source)},
  whole_query_methods: [list_latest, create, pinning].map { |node| {start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  original_list_methods: methods.select { |node| (names + %i[initialize load_topics category_user_lookup]).include?(node.name) }.map { |node|
    {name: node.name, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  guarded_changes: changes, live_values_used_as_inputs: false,
  candidate_sha256: {"topic_query_list_latest.rb" => Digest::SHA256.hexdigest(query), "topic_list.rb" => Digest::SHA256.hexdigest(list)},
  unsupported_profiles: %w[authenticated nonlatest unlimited non_en_locale serialization_request],
  full_query_accepted: false, json_request_accepted: false, page_accepted: false}
File.write(File.join(directory, "MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
