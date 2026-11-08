# frozen_string_literal: true
# Reproducible PARTIAL default_results component, not a new topic backend.
require "prism"
require "json"
require "digest"
root = File.expand_path("../..", __dir__)
source_path = File.join(root, "fidelity/source/discourse/lib/topic_query.rb")
source = File.binread(source_path)
tree = Prism.parse(source)
owner = tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :default_results }
def stage_nodes(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| stage_nodes(child, result) }
  result
end
nodes = stage_nodes(method)
texts = [
  "options.reverse_merge!(@options)",
  "options.reverse_merge!(per_page: per_page_setting) unless options[:limit] == false",
  "viewing_own_topics = @user && @user.id == options[:filtered_to_user]",
  "result = Topic.includes(:category)",
  "result = result.merge(all_listable_topics)",
  "result = result.limit(options[:per_page]&.to_i) unless options[:limit] == false",
  "result = result.visible if options[:visible]",
]
selected = texts.map do |text|
  found = nodes.select { |node| node.slice == text }
  # Prism may wrap the exact same span in a StatementsNode; choose its
  # actual statement rather than making multiple copies of one source span.
  found = found.reject { |node| node.is_a?(Prism::StatementsNode) }
  raise "source statement changed: #{text}" unless found.length == 1
  found.first
end
selected += nodes.select { |node| node.is_a?(Prism::IfNode) && ["options[:visible].nil?", "options[:page]"].include?(node.predicate.slice) }
selected << nodes.find { |node| node.is_a?(Prism::LocalVariableWriteNode) && node.name == :all_listable_topics }
raise "missing default_results anchors" unless selected.length == 10 && selected.none?(&:nil?)
selected.sort_by! { |node| node.location.start_offset }
constant = owner.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :DEFAULT_PER_PAGE_COUNT }
per_page = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :per_page_setting }
body = selected.map(&:slice).join("\n\n") + "\n\nresult\n"
component = <<~RUBY
  # frozen_string_literal: true
  # PARTIAL default_results: anonymous default visibility/security/limit/offset.
  # Ordering/category/tag/search/nested/list hydration are NOT admitted here.
  class TopicQueryVisiblePage
    #{constant.slice}

    def initialize
      @guardian = Guardian.new
      @user = nil
      @options = {}
    end

    def self.validate_options!(options)
      allowed = [:page, :per_page, :visible, :limit]
      options.each_key do |key|
        raise ArgumentError, "unsupported partial default_results option: \#{key}" unless allowed.include?(key)
      end
      page = options[:page]
      per_page = options[:per_page]
      raise ArgumentError, "unsupported page" if page && (!page.is_a?(Integer) || page < 0 || page > 100)
      raise ArgumentError, "unsupported per_page" if per_page && (!per_page.is_a?(Integer) || per_page < 1 || per_page > 100)
      raise ArgumentError, "anonymous visibility must be default/true" unless options[:visible].nil? || options[:visible] == true
      raise ArgumentError, "unsupported limit" unless options[:limit].nil? || options[:limit] == false
      raise ArgumentError, "unlimited paging requires per_page" if options[:limit] == false && page && !per_page
    end

    def results(options = {})
      self.class.validate_options!(options)
  #{body.lines.map { |line| "    " + line }.join}
    end

    #{per_page.slice}
  end
RUBY
raise "invalid shared partial component" unless Prism.parse(component).success?
directory = File.join(root, "fidelity/progressive/stage1")
Dir.mkdir(File.dirname(directory)) unless Dir.exist?(File.dirname(directory))
Dir.mkdir(directory) unless Dir.exist?(directory)
File.binwrite(File.join(directory, "topic_query_visible_page.rb"), component)
File.binwrite(File.join(directory, "original-expression.rb"), body)
manifest = {profile: "PARTIAL default_results visible paged relation ONLY", baseline_revision: "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
  source: "lib/topic_query.rb", source_sha256: Digest::SHA256.hexdigest(source),
  selected_statements: selected.map { |node| {start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    start_line: node.location.start_line, end_line: node.location.end_line, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  whole_method_dependencies: [constant, per_page].map { |node| {start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} },
  source_operation_order_preserved: true, live_values_used_as_inputs: false,
  candidate_sha256: Digest::SHA256.hexdigest(component), original_expression_sha256: Digest::SHA256.hexdigest(body),
  omitted_profiles: %w[authenticated category tags search ordering nested_replies list_hydration],
  complete_default_results_accepted: false, full_query_accepted: false, page_accepted: false}
File.write(File.join(directory, "MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
