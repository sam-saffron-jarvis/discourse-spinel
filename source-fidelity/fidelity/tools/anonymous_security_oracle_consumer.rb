# frozen_string_literal: true
# TEST-only selected expression on actual fully booted original Rails. No method
# on Guardian/AnonymousUser/SiteSetting is replaced, wrapped, disabled or stubbed.
load ENV.fetch("FIDELITY_SECURITY_CONSUMER")
class SecurityProbe
  def self.relation
    query = TopicQuery.new(nil)
    query.instance_eval(File.binread(ENV.fetch("FIDELITY_TOPIC_QUERY_EXPRESSION")),
                        File.expand_path("lib/topic_query.rb"), 1)
  end
end

sources = {
  initialize: Guardian.instance_method(:initialize),
  filter: Guardian.instance_method(:filter_allowed_categories),
  allowed: Guardian.instance_method(:allowed_category_ids),
  secure: Guardian.instance_method(:secure_category_ids),
  identity: Guardian.instance_method(:is_admin?),
  anonymous_admin: Guardian::AnonymousUser.instance_method(:admin?),
  anonymous_secure: Guardian::AnonymousUser.instance_method(:secure_category_ids),
}
expected = {initialize: ["lib/guardian.rb", 122], filter: ["lib/guardian/topic_guardian.rb", 272],
            allowed: ["lib/guardian/category_guardian.rb", 61], secure: ["lib/guardian/category_guardian.rb", 56],
            identity: ["lib/guardian.rb", 140], anonymous_admin: ["lib/guardian.rb", 44],
            anonymous_secure: ["lib/guardian.rb", 80]}
sources.each do |name, method|
  path, line = expected.fetch(name)
  raise "applicable plugin changed #{name}; expand closure, do not omit it" unless method.source_location == [File.expand_path(path), line]
end
getter_source = SiteSetting.method(:suppress_secured_categories_from_admin).source_location
raise "actual runtime getter declaration changed" unless getter_source == [File.expand_path("lib/site_setting_extension.rb"), 1143]
presence = nil.method(:presence)
raise "unproved nil presence protocol" unless presence.owner == Object && presence.source_location.first.include?("active_support/core_ext/object/blank.rb")
raise "unproved nil identity protocol" unless nil.method(:equal?).owner == BasicObject
raise "missing live restricted category input" unless Category.where(read_restricted: true).exists?
raise "missing live public category input" unless Category.where(read_restricted: false).exists?

# Installed AFTER real boot and BEFORE the common observation probe. Boot-time
# and separately forced cold-getter reachability are different experiments, owned
# by the coordinator's Rails lane; no warm value is substituted here.
counts = Hash.new(0)
getter_calls = 0
owner_classes = [Guardian, Guardian::AnonymousUser, TopicGuardian, CategoryGuardian]
trace = TracePoint.new(:call, :c_call) do |event|
  if event.self.equal?(SiteSetting) && event.method_id == :suppress_secured_categories_from_admin
    getter_calls += 1
  end
  if owner_classes.include?(event.defined_class) &&
      [:initialize, :is_admin?, :admin?, :filter_allowed_categories, :allowed_category_ids, :secure_category_ids].include?(event.method_id)
    counts[event.method_id.to_s] += 1
  end
end
trace.enable
at_exit do
  trace.disable
  successful = $!.nil?
  puts "FIDELITY_ANONYMOUS_REACHABILITY " + JSON.generate({
    scope: "selected anonymous security probe after actual Rails boot; NOT boot or forced cold getter or full /latest request",
    successful_probe: successful, setting_getter_calls: getter_calls, counts: counts,
    effective_sources: sources.transform_values { |method| method.source_location },
    nil_presence: presence.source_location, setting_getter_source: getter_source,
    guardian_ancestors: Guardian.ancestors.map(&:name), plugin_names: Discourse.plugins.map(&:name),
  })
  raise "anonymous selected probe unexpectedly read the admin setting" unless getter_calls == 0
end
