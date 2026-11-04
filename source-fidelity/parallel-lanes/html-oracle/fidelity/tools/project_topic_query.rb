# frozen_string_literal: true
# Audited PARTIAL TopicQuery foundation. No method text is synthesized or
# rewritten: unselected bytes become spaces, keeping offsets and line numbers.
# The complete input files remain locked separately. This is NOT default_results.
require_relative "project_source"

maps = JSON.parse(File.read(File.join(output = ARGV.fetch(1), "projection-map.json")))
root = ARGV.fetch(0)
specs = {
  "lib/guardian/topic_guardian.rb" => ["TopicGuardian", %i[filter_allowed_categories]],
  "lib/guardian/category_guardian.rb" => ["CategoryGuardian", %i[secure_category_ids allowed_category_ids]],
  "lib/guardian.rb" => ["Guardian", %i[initialize is_admin?]],
  "lib/topic_query.rb" => ["TopicQuery", []],
  # A declaration without the settings DSL is NOT a callable setting reader.
  # Keeping the missing contract visible is intentional; never install a fake
  # getter or freeze the YAML default to make the native compile pass.
  "app/models/site_setting.rb" => ["SiteSetting", []],
}

specs.each do |path, (owner, methods)|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  raise "invalid source #{path}" unless parsed.success?
  all = nodes(parsed.value)
  declaration = all.find { |n| (n.is_a?(Prism::ClassNode) || n.is_a?(Prism::ModuleNode)) && n.constant_path.slice == owner }
  raise "missing #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
  end
  header = lambda do |node, role|
    ending = source.index("\n", node.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, node.location.start_offset, ending - node.location.start_offset), role)
    copy.call(node.end_keyword_loc, "#{role}_end")
  end
  header.call(declaration, "owner")
  direct = declaration.body.body
  methods.each do |name|
    selected = direct.select { |n| n.is_a?(Prism::DefNode) && n.name == name && n.receiver.nil? }
    raise "ambiguous/missing #{owner}##{name}" unless selected.length == 1
    copy.call(selected.first.location, "method:#{name}")
  end
  if owner == "Guardian"
    %w[CategoryGuardian TopicGuardian].each do |mixin|
      selected = direct.find { |n| n.is_a?(Prism::CallNode) && n.name == :include && n.arguments.arguments.first.slice == mixin }
      raise "missing #{mixin}" unless selected
      copy.call(selected.location, "include:#{mixin}")
    end
    anonymous = direct.find { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == "AnonymousUser" }
    header.call(anonymous, "nested:AnonymousUser")
    %i[blank? admin? secure_category_ids].each do |name|
      selected = anonymous.body.body.find { |n| n.is_a?(Prism::DefNode) && n.name == name }
      raise "missing AnonymousUser##{name}" unless selected
      copy.call(selected.location, "AnonymousUser##{name}")
    end
  elsif owner == "TopicQuery"
    accessors = direct.find { |n| n.is_a?(Prism::CallNode) && n.name == :attr_accessor }
    copy.call(accessors.location, "original_test_injection_accessor")
    method = direct.find { |n| n.is_a?(Prism::DefNode) && n.name == :default_results }
    header.call(method, "PARTIAL_method:default_results")
    statements = nodes(method)
    {
      "result = Topic.includes(:category)" => "category_preloaded_receiver",
      "all_listable_topics" => "original_guardian_composition",
      "result = result.merge(all_listable_topics)" => "original_non_pm_merge",
    }.each do |text, role|
      selected = statements.select do |n|
        n.is_a?(Prism::LocalVariableWriteNode) && (text == "all_listable_topics" ? n.name == :all_listable_topics : n.slice == text)
      end
      raise "ambiguous/missing #{role}" unless selected.length == 1
      copy.call(selected.first.location, role)
    end
  end
  if owner == "TopicQuery"
    expression = source.gsub(/[^\n]/, " ")
    spans.select { |span| %w[category_preloaded_receiver original_guardian_composition original_non_pm_merge].include?(span[:role]) }.each do |span|
      start = span[:start_byte]
      expression[start...span[:end_byte]] = source[start...span[:end_byte]]
    end
    File.binwrite(File.join(output, "topic-query-expression.rb"), expression)
  end
  destination = "app/models/" + File.basename(path)
  File.binwrite(File.join(output, destination), projected)
  maps << { source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: "PARTIAL TopicQuery security projection; no full boot, settings reader, authenticated User closure or complete default_results claimed" }
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
