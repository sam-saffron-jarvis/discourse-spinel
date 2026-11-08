# frozen_string_literal: true
# Compile-/analysis-only audit of finite-source staging obligations. This does
# not load a plugin, invoke its DSL, emit executable application code or accept
# activation. Complete original scripts remain byte-identical locked inputs.
require "prism"
require "json"
require "digest"
root, trace_path = ARGV
raise "usage: audit_plugin_staging.rb ORIGINAL_SOURCE_ROOT ACTUAL_TRACE_EVIDENCE" unless root && trace_path
owner_path = "lib/plugin/instance.rb"
owner_bytes = File.binread(File.join(root, owner_path))
parsed = Prism.parse(owner_bytes)
owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "Plugin::Instance" }
activate = owner.body.body.find { |node| node.is_a?(Prism::DefNode) && node.name == :activate! }
raise "original producer changed" unless activate.body.body.first.slice == "instance_eval File.read(path), path"
evidence = JSON.parse(File.read(trace_path))
trace = evidence.fetch("actual_rails_plugin_activation")
raise "unsuccessful producer trace" unless trace.fetch("successful_oracle")
raise "original owner is not pinned by producer evidence" unless Digest::SHA256.hexdigest(owner_bytes) == evidence.fetch("source_hashes").fetch(owner_path)
span = lambda do |node|
  { start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    line: node.location.start_line, text_sha256: Digest::SHA256.hexdigest(node.slice) }
end
walk = lambda do |node, parents, &visit|
  visit.call(node, parents)
  node.compact_child_nodes.each { |child| walk.call(child, parents + [node], &visit) }
end
files = %w[discourse-assign discourse-events discourse-solved].map do |plugin|
  path = "plugins/#{plugin}/plugin.rb"
  bytes = File.binread(File.join(root, path))
  raise "unlocked script #{path}" unless Digest::SHA256.hexdigest(bytes) == evidence.fetch("source_hashes").fetch(path)
  ordinary = Prism.parse(bytes, filepath: File.join(root, path))
  scoped = Prism.parse(bytes, filepath: File.join(root, path), scopes: [Prism::Scope.new(activate.locals, [])])
  raise "invalid original #{path}" unless ordinary.success? && scoped.success?
  binding_signature = lambda do |node|
    if node.respond_to?(:name) && activate.locals.include?(node.name) &&
        (node.class.name.include?("LocalVariable") || node.is_a?(Prism::CallNode))
      { kind: node.class.name, name: node.name, depth: node.respond_to?(:depth) ? node.depth : nil }
    end
  end
  nodes = {}
  walk.call(ordinary.value, []) do |node, _|
    signature = binding_signature.call(node)
    nodes[[node.location.start_offset, node.location.end_offset]] = signature if signature
  end
  changed_bindings = []
  walk.call(scoped.value, []) do |node, _|
    key = [node.location.start_offset, node.location.end_offset]
    before = nodes[key]
    after = binding_signature.call(node)
    if before && after && before != after
      changed_bindings << span.call(node).merge(before: before, with_actual_caller_locals: after)
    end
  end
  declarations, returns, locations, requires = [], [], [], []
  walk.call(ordinary.value, []) do |node, parents|
    case node
    when Prism::ModuleNode, Prism::ClassNode
      declarations << span.call(node).merge(kind: node.class.name, name: node.constant_path.slice)
    when Prism::ReturnNode
      frames = parents.select { |p| p.is_a?(Prism::DefNode) || p.is_a?(Prism::LambdaNode) || p.is_a?(Prism::CallNode) }
      returns << span.call(node).merge(enclosing: frames.map { |p| p.is_a?(Prism::CallNode) ? p.name : p.is_a?(Prism::DefNode) ? "def:#{p.name}" : "lambda" })
    when Prism::SourceFileNode, Prism::SourceLineNode
      locations << span.call(node).merge(kind: node.class.name)
    when Prism::CallNode
      if node.name == :require_relative && node.receiver.nil?
        requires << span.call(node).merge(literal: node.arguments&.arguments&.one? && node.arguments.arguments.first.is_a?(Prism::StringNode))
      end
    end
  end
  method_prefix = "class StagingSyntaxReceiver\n  def activate!\n    instance_eval do\n"
  candidate = Prism.parse(method_prefix + bytes + "\n    end\n  end\nend\n")
  # Parse ONLY: top-level relocation fixes grammar, not lexical/frame semantics.
  top = Prism.parse("receiver.instance_eval do\n" + bytes + "\nend\n")
  { source: path, bytes: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes),
    declarations: declarations, returns: returns, source_locations: locations,
    relative_requires: requires, actual_caller_binding_changes: changed_bindings,
    in_method_literal_block_syntax_errors: candidate.errors.map(&:message),
    top_level_literal_block_syntax_valid: top.success?,
    semantic_equivalence_proved: false, native_executed: false }
end
puts JSON.pretty_generate({
  scope: "whole original script staging design/rejection audit ONLY; no activation admission",
  accepted: false, source_owner: owner_path, source_owner_sha256: Digest::SHA256.hexdigest(owner_bytes),
  activation_producer: span.call(activate), actual_caller_locals: activate.locals,
  actual_source_producer_events: trace.fetch("events").select { |event| %w[activate! enabled_site_setting load_settings provider after_initialize notify_after_initialize reloadable_patch add_custom_filter register].include?(event["method"]) && event["event"] != "b_call" },
  scripts: files,
  required_before_admission: ["receiver/self and nested callback owner", "lexical constant context and actual caller local bindings", "source filename/line and require_relative/cache identity", "activation/nonlocal return and method-definition rebinding frames", "captured locals/callables/arity", "complete original activation/configuration/initializer/registration effects in order", "runtime resource byte identity guards and unknown-world refusal"],
  decision: "REJECT unproved literal-block/hoisting/Proc relocation shortcuts. Use a frame-preserving finite-source mechanism only after each obligation is proved; otherwise select an evidenced registry prerequisite."
})
