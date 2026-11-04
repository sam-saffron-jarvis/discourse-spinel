# frozen_string_literal: true
# Oracle-only TEST consumer: evaluate the byte-audited three original statements
# on a fully initialized original TopicQuery. Never replace any original method.
load ENV.fetch("FIDELITY_SECURITY_CONSUMER")
class SecurityProbe
  def self.relation
    query = TopicQuery.new(nil)
    query.instance_eval(File.binread(ENV.fetch("FIDELITY_TOPIC_QUERY_EXPRESSION")),
                        File.expand_path("lib/topic_query.rb"), 1)
  end
end

sources = {
  filter: Guardian.instance_method(:filter_allowed_categories),
  allowed: Guardian.instance_method(:allowed_category_ids),
  secure: Guardian.instance_method(:secure_category_ids),
  identity: Guardian.instance_method(:is_admin?),
  anonymous_secure: Guardian::AnonymousUser.instance_method(:secure_category_ids),
}
expected = {filter: ["lib/guardian/topic_guardian.rb", 272],
            allowed: ["lib/guardian/category_guardian.rb", 61],
            secure: ["lib/guardian/category_guardian.rb", 56],
            identity: ["lib/guardian.rb", 140], anonymous_secure: ["lib/guardian.rb", 80]}
sources.each do |name, method|
  path, line = expected.fetch(name)
  raise "applicable plugin changed #{name}; expand closure, do not omit it" unless method.source_location == [File.expand_path(path), line]
end
raise "missing live restricted category negative input" unless Category.where(read_restricted: true).exists?
raise "missing live public category input" unless Category.where(read_restricted: false).exists?
# These actual identity/admin branches are Rails-ONLY observations, NOT native
# evidence. No user, permission, setting, callback or plugin method is stubbed.
branches = []
[nil, User.where(admin: false).order(:id).first, User.where(admin: true).order(:id).first].each do |user|
  raise "identity fixture missing" if branches.length > 0 && user.nil?
  guardian = Guardian.new(user)
  query = TopicQuery.new(user, guardian: guardian)
  relation = query.instance_eval(File.binread(ENV.fetch("FIDELITY_TOPIC_QUERY_EXPRESSION")), File.expand_path("lib/topic_query.rb"), 1)
  fixture = relation.from(ENV.fetch("FIDELITY_SECURITY_FIXTURE_FROM")).order("topics.id ASC")
  branches << {user_id: user&.id, anonymous: guardian.anonymous?, admin: guardian.is_admin?,
               allowed_ids: guardian.allowed_category_ids, fixture_ids: fixture.map(&:id),
               filter_source: guardian.method(:filter_allowed_categories).source_location}
end
# Demonstrate the actual cold-getter closure, not just the warm value observed
# after Rails boot. Evict ONLY this process' memoized settings hash. This is not
# a source stub or a setting mutation; original refresh!/callbacks run unchanged
# against the authorized disposable ORACLE fixture and read-only PG.
write_log = ENV.fetch("FIDELITY_VALKEY_WRITE_LOG")
def fidelity_effect_lines(path)
  File.open(path) do |file|
    file.flock(File::LOCK_SH)
    file.readlines
  end
end
before_effects = fidelity_effect_lines(write_log).length
cold_started = Time.now.utc.iso8601(6)
containers = SiteSetting.instance_variable_get(:@containers)
raise "settings container unavailable" unless containers.is_a?(Hash)
containers.delete(SiteSetting.provider.current_site)
cold_value = SiteSetting.suppress_secured_categories_from_admin
cold_finished = Time.now.utc.iso8601(6)
cold_effects = fidelity_effect_lines(write_log).drop(before_effects).map { |line| JSON.parse(line) }
getter_effects = cold_effects.select do |effect|
  effect["caller"].any? { |frame| frame.include?(File.expand_path(__FILE__)) } &&
    effect["caller"].any? { |frame| frame.include?("site_setting_extension.rb:1165") }
end
raise "cold getter did not exercise actual refresh effects" unless getter_effects.any? { |effect| effect["command"] == "del" }
raise "cold getter cache publication was omitted" unless getter_effects.any? { |effect| effect["caller"].any? { |frame| frame.include?("app/models/site.rb:313") } }
puts "FIDELITY_SETTINGS_COLD " + JSON.generate({
  source: SiteSetting.method(:suppress_secured_categories_from_admin).source_location,
  value: cold_value, effect_count: cold_effects.length, getter_effect_count: getter_effects.length,
  commands: getter_effects.map { |effect| effect["command"] }.uniq,
  first_started: cold_started, finished: cold_finished,
  effects: getter_effects,
  scope: "actual Rails cold-getter experiment ONLY; native effects not authorized/executed",
})

puts "FIDELITY_SECURITY_ORACLE " + JSON.generate({
  scope: "actual Rails branches only; native settings/User closure remains incomplete",
  setting: SiteSetting.suppress_secured_categories_from_admin,
  setting_source: SiteSetting.method(:suppress_secured_categories_from_admin).source_location,
  guardian_ancestors: Guardian.ancestors.map(&:name), sources: sources.transform_values { |m| m.source_location },
  plugin_names: Discourse.plugins.map(&:name), branches: branches,
})
