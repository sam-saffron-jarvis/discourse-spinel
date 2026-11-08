# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"

def generate_host_authorization(root, framework_read, parts)
  source_path = "actionpack-8.1.4/lib/action_dispatch/middleware/host_authorization.rb"
  source = framework_read.call(source_path)
  owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ClassNode).first
  raise "actual host authorization owner changed" unless owner.constant_path.slice == "HostAuthorization"
  selected = owner.body.body.grep(Prism::ConstantWriteNode)
  permissions = owner.body.body.grep(Prism::ClassNode).find { |node| node.constant_path.slice == "Permissions" }
  raise "actual host permissions missing" unless permissions
  selected << permissions
  methods = %i[initialize call blocked_hosts excluded? mark_as_authorized].map do |name|
    node = owner.body.body.grep(Prism::DefNode).find { |item| item.name == name }
    raise "actual host method changed #{name}" unless node
    selected << node
    code = node.slice
    if name == :initialize
      code = code.sub("@response_app = response_app || DefaultResponseApp.new",
        'raise ArgumentError, "unsupported custom host response app profile" unless response_app.nil?')
    elsif name == :call
      code = code.sub("Request.new(env)", "Rack::CoreRequest.new(env)")
      code = code.sub("@response_app.call(env)", 'raise ArgumentError, "unsupported blocked-host JSON request profile"')
    elsif name == :blocked_hosts
      code = code.sub("forwarded_host.blank?", "PortableResponseMiddlewareDeclarations.blank_header?(forwarded_host)")
    end
    code
  end
  selected.each do |node|
    parts << {source: source_path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(node.slice)}
  end
  configuration_path = "railties-8.1.4/lib/rails/application/configuration.rb"
  configuration = framework_read.call(configuration_path)
  find_nodes = lambda do |tree, &predicate|
    found = []
    visit = lambda do |node|
      found << node if predicate.call(node)
      node.compact_child_nodes.each { |child| visit.call(child) }
    end
    visit.call(tree)
    found
  end
  defaults = find_nodes.call(Prism.parse(configuration).value) do |node|
    node.is_a?(Prism::InstanceVariableWriteNode) && node.name == :@hosts &&
      node.value.slice.include?("ActionDispatch::HostAuthorization::ALLOWED_HOSTS_IN_DEVELOPMENT")
  end
  raise "actual development host defaults changed" unless defaults.length == 1
  default_hosts = defaults.first.value
  parts << {source: configuration_path, start_byte: default_hosts.location.start_offset, end_byte: default_hosts.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(default_hosts.slice)}
  development_path = "config/environments/development.rb"
  development, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8:#{development_path}")
  raise "actual application development config changed" unless status.success? && File.binread(File.join(root, "discourse", development_path)) == development.b
  patterns = find_nodes.call(Prism.parse(development).value) do |node|
    node.is_a?(Prism::CallNode) && node.name == :<< && node.receiver&.slice == "config.hosts"
  end
  raise "actual application host regexp changed" unless patterns.length == 1
  pattern = patterns.first.arguments.arguments.first
  text = <<~RUBY
    # frozen_string_literal: true
    # GENERATED actual Rails/Discourse development host classifier and scope.
    # Blocked-host debug HTML/custom response applications explicitly refuse.
    require "ipaddr"
    module ActionDispatch
      class HostAuthorization
        #{selected.grep(Prism::ConstantWriteNode).map(&:slice).join("\n")}
        #{permissions.slice}
        #{methods.join("\n\n")}
      end
    end
    module PortableHostAuthorizationDeclarations
      def self.hosts
        raise ArgumentError, "unsupported non-development host authorization profile" unless ENV.fetch("RAILS_ENV") == "development"
        # The deprecated option also emits a real deprecation event at boot.
        # Do not silently omit that event or pretend this profile handles it.
        raise ArgumentError, "unsupported deprecated development host configuration" unless ENV["DISCOURSE_DEV_HOSTS"].nil?
        hosts = #{default_hosts.slice}
        hosts << #{pattern.slice}
        hosts
      end
    end
  RUBY
  raise "invalid source host component" unless Prism.parse(text).success?
  target = "compat/framework/portable_host_authorization.rb"
  File.binwrite(File.join(root, "fidelity", target), text)
  {candidate: target, candidate_sha256: Digest::SHA256.hexdigest(text),
   application_source_sha256: {development_path => Digest::SHA256.hexdigest(development)},
   application_selected_spans: [{source: development_path, start_byte: pattern.location.start_offset, end_byte: pattern.location.end_offset,
     text_sha256: Digest::SHA256.hexdigest(pattern.slice)}],
   auxiliary_source_sha256: {"spinel/packages/ipaddr/ipaddr.rb" => Digest::SHA256.file(File.join(root, "spinel/packages/ipaddr/ipaddr.rb")).hexdigest},
   original_class: "ActionDispatch::HostAuthorization", actual_class: "ActionDispatch::HostAuthorization",
   native_integer_profile: "--int-overflow=promote (actual IPAddr IPv6 masks require 128-bit integers)",
   transformations: ["Request env adapter retains original header access/host normalization and shared env writes",
     "Actual permissions/constants and development host declarations retained; RAILS_DEVELOPMENT_HOSTS stays live",
     "Default blocked-host debug HTML and custom response applications are unsupported profiles, never anonymous success",
     "Deprecated DISCOURSE_DEV_HOSTS deprecation side effect is unsupported, explicitly refused"],
   full_stack_accepted: false, captured_permissions_or_runtime_hosts: false}
end
