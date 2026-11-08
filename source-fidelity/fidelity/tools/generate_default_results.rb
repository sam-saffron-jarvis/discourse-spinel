# frozen_string_literal: true
# Supported anonymous core default_results decomposition. Every omitted branch
# has an explicit request/identity guard; no live setting value is an input.
require "prism"
require "json"
require "digest"
root = File.expand_path("../..", __dir__)
source_path = File.join(root, "fidelity/source/discourse/lib/topic_query.rb")
source = File.binread(source_path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
method = methods.find { |node| node.name == :default_results }
changes = []
unsupported = %w[search state before bumped_before status filter f include_pms include_all_pms filtered_to_user skip_ordering tags match_all_tags exclude_tag guardian]
method.body.body.grep(Prism::IfNode).each do |node|
  predicate = node.predicate.slice
  replacement = nil
  reason = nil
  if predicate == "@user"
    replacement, reason = "", "supported component constructs only original anonymous identity"
  elsif predicate == "options[:include_pms] || options[:include_all_pms]"
    replacement, reason = node.subsequent.statements.slice, "include_pms/include_all_pms request keys explicitly refused"
  elsif ["search = options[:search].presence", "state = options[:state]", "before = options[:before]",
         "bumped_before = options[:bumped_before]", "status = options[:status]",
         "(filter = options[:filter] || options[:f]) && @user"].include?(predicate)
    replacement, reason = "", "request profile keys explicitly refused; anonymous component has no authenticated branch"
  end
  changes << [node, replacement, reason] unless replacement.nil?
end
raise "default_results guarded branch set changed" unless changes.length == 8
body = method.slice.dup
changes.sort_by { |node, _, _| -node.location.start_offset }.each do |node, replacement, _|
  body[node.location.start_offset - method.location.start_offset, node.location.length] = replacement
end
body = body.sub("def default_results(options = {})", "def results(options = {})\n    self.class.validate_options!(options)\n    self.class.validate_options!(@options, true)\n    raise ArgumentError, \"unsupported identity profile\" unless @user.nil? && @guardian.instance_of?(Guardian)")
body = body.sub("Category.subcategory_ids(category_id)", "subcategory_ids(category_id)")

# The common readonly category adapter was already compared against real Rails;
# preserve its recursive SQL, never substitute a topic-query SQL implementation.
category_path = File.join(root, "fidelity/compat/discourse/app/models/category.rb")
category_source = File.binread(category_path)
category_owner = Prism.parse(category_source).value.statements.body.grep(Prism::ClassNode).first
subcategory = category_owner.body.body.grep(Prism::DefNode).find { |node| node.name == :subcategory_ids }
subcategory_source = subcategory.slice.sub("def self.subcategory_ids", "def subcategory_ids")

filter = methods.find { |node| node.name == :filter_by_tags }
branches = filter.body.body.grep(Prism::IfNode).first
no_tags = branches.subsequent
raise "no_tags source branch changed" unless no_tags.is_a?(Prism::IfNode) && no_tags.predicate.slice.include?("@options[:no_tags]")
filter_source = "def filter_by_tags(result)\n    #{no_tags.slice}\n    result\n  end"
# In Prism the elsif keyword belongs to the enclosing source if. Ground that
# source branch as the guarded helper's first if, retaining its predicate/body.
filter_source = filter_source.sub("elsif ", "if ")
helper_names = %i[per_page_setting apply_ordering get_category_id]
helpers = helper_names.map { |name| methods.find { |node| node.name == name }.slice }
constants = owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[DEFAULT_PER_PAGE_COUNT SORTABLE_MAPPING].include?(node.name) }
allowed = %w[page per_page visible limit category no_subcategories no_definitions except_topic_ids topic_ids order ascending no_tags min_posts max_posts]
component = <<~RUBY
  # frozen_string_literal: true
  # Complete default_results BEHAVIOR for the explicitly supported anonymous
  # profile below, not all TopicQuery request options, latest/list or page.
  class TopicQueryDefaultResults
    #{constants.map(&:slice).join("\n\n  ")}
    attr_accessor :options
    attr_reader :user, :guardian

    def initialize(options = {})
      self.class.validate_options!(options)
      @options = options.dup
      @user = nil
      @guardian = Guardian.new(nil)
    end

    def self.validate_options!(options, internal = false)
      allowed = #{allowed.map { |key| ":#{key}" }.inspect.gsub('"', '')}
      allowed << :category_id if internal
      options.each_key { |key| raise ArgumentError, "unsupported default_results profile option: \#{key}" unless allowed.include?(key) }
      raise ArgumentError, "unsupported nested replies profile" if SiteSetting.nested_replies_enabled
      raise ArgumentError, "unsupported localization profile" if SiteSetting.content_localization_enabled
      [:page, :per_page, :min_posts, :max_posts].each do |key|
        value = options[key]
        raise ArgumentError, "unsupported integer option: \#{key}" if value && (!value.is_a?(Integer) || value < 0 || value > 1000)
      end
      raise ArgumentError, "per_page must be positive" if options[:per_page] == 0
      raise ArgumentError, "unlimited paging needs per_page" if options[:limit] == false && options[:page] && !options[:per_page]
      raise ArgumentError, "unsupported limit" unless options[:limit].nil? || options[:limit] == false
      raise ArgumentError, "anonymous visibility must be default/true" unless options[:visible].nil? || options[:visible] == true
      raise ArgumentError, "unsupported category" unless options[:category].nil? || options[:category].is_a?(String)
      [:no_subcategories, :no_definitions, :no_tags].each do |key|
        value = options[key]
        raise ArgumentError, "unsupported boolean option: \#{key}" unless value.nil? || value == true || value == false || value == "true" || value == "false"
      end
      [:except_topic_ids, :topic_ids].each do |key|
        value = options[key]
        unless value.nil?
          raise ArgumentError, "unsupported id list" unless value.is_a?(Array)
          value.each { |id| raise ArgumentError, "unsupported id" unless id.is_a?(Integer) }
        end
      end
      order = options[:order]
      raise ArgumentError, "unsupported order" unless order.nil? || order == "default" || (SORTABLE_MAPPING.key?(order) && order != "op_likes")
      ascending = options[:ascending]
      raise ArgumentError, "unsupported ascending" unless ascending.nil? || ascending == "true" || ascending == "false"
    end

    #{body}

    #{helpers.join("\n\n  ")}

    #{filter_source}

    #{subcategory_source}
  end
RUBY
raise "invalid supported default_results component" unless Prism.parse(component).success?
directory = File.join(root, "fidelity/progressive/stage2")
Dir.mkdir(directory) unless Dir.exist?(directory)
File.binwrite(File.join(directory, "topic_query_default_results.rb"), component)
manifest = {profile: "supported anonymous core default_results behavior ONLY", baseline_revision: "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  source: "lib/topic_query.rb", source_sha256: Digest::SHA256.hexdigest(source),
  original_method: {start_byte: method.location.start_offset, end_byte: method.location.end_offset, text_sha256: Digest::SHA256.hexdigest(method.slice)},
  guarded_branches: changes.map { |node, replacement, reason| {start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice), replacement_sha256: Digest::SHA256.hexdigest(replacement), reason: reason} },
  dependencies: (constants + methods.select { |node| helper_names.include?(node.name) } + [filter]).map { |node|
    {start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  readonly_category_candidate_sha256: Digest::SHA256.hexdigest(category_source), distributed_category_cache_equivalence_accepted: false,
  candidate_sha256: Digest::SHA256.hexdigest(component), unsupported_request_keys: unsupported,
  unsupported_live_feature_profiles: %w[nested_replies_enabled content_localization_enabled],
  identity_api: "genuine anonymous Guardian; user/guardian read-only, nonanonymous identities not admitted",
  source_operation_order_preserved: true, live_values_used_as_inputs: false,
  full_query_accepted: false, page_accepted: false}
File.write(File.join(directory, "MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
