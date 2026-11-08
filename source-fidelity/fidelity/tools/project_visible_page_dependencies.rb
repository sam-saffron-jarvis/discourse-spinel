# frozen_string_literal: true
# Necessary real visibility API dependencies only, not the full query closure.
require "prism"
require "json"
require "digest"
root, output = ARGV
map_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(map_path))
specs = {
  "lib/guardian.rb" => ["Guardian", %i[is_staff?], %i[staff? has_trust_level?]],
  "lib/guardian/topic_guardian.rb" => ["TopicGuardian", %i[can_see_unlisted_topics?], []],
  "lib/trust_level.rb" => ["TrustLevel", %i[[] valid? valid_range], []],
}
specs.each do |path, (name, names, anonymous)|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  owner = parsed.value.statements.body.find { |node| (node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)) && node.constant_path.slice == name }
  destination = "app/models/" + File.basename(path)
  prior = map.find { |entry| entry["generated"] == destination }
  projection = prior ? File.binread(File.join(output, destination)) : source.gsub(/[^\n]/, " ")
  spans = prior ? prior["selected_spans"] : []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  unless prior
    line_end = source.index("\n", owner.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, line_end - owner.location.start_offset), "source_visibility_dependency")
    copy.call(owner.end_keyword_loc, "source_visibility_dependency_end")
    exception = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "InvalidTrustLevel" }
    copy.call(exception.location, "actual_source_exception") if exception
  end
  names.each do |method_name|
    method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == method_name }
    raise "visibility method changed: #{name} #{method_name}" unless method
    copy.call(method.location, "whole_source_visibility_method:#{method_name}")
  end
  unless anonymous.empty?
    identity = owner.body.body.grep(Prism::ClassNode).find { |node| node.constant_path.slice == "AnonymousUser" }
    anonymous.each do |method_name|
      method = identity.body.body.grep(Prism::DefNode).find { |node| node.name == method_name }
      raise "anonymous source method changed: #{method_name}" unless method
      copy.call(method.location, "whole_source_anonymous_method:#{method_name}")
    end
  end
  raise "invalid source visibility projection" unless Prism.parse(projection).success?
  File.binwrite(File.join(output, destination), projection)
  map.reject! { |entry| entry["generated"] == destination }
  map << {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "Stage1 additional real visibility dependencies ONLY; full default_results/query not admitted"}
end
File.write(map_path, JSON.pretty_generate(map) + "\n")
