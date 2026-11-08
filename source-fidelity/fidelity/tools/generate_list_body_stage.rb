# frozen_string_literal: true
# Real list body/model continuation, never a supplied payload or returned page.
require "prism"
require "digest"
require "json"
require "yaml"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, original: {}, spans: [], framework: [], full_body_accepted: false, html200_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "body source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  proof[:original][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |text, name, path|
  found = []
  walk = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(text).value)
  raise "body method ambiguous #{path}:#{name}" unless found.size == 1
  node = found.first
  proof[:spans] << {source: path, name: name, first_byte: node.location.start_offset, last_byte: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
append = lambda do |path, source|
  target = File.join(app, path)
  File.write(target, File.read(target).sub(/end\s*\z/) { "#{source}\nend\n" })
end
poster = select.call(read.call("app/models/topic_poster.rb"), :name_and_description, "app/models/topic_poster.rb")
user = select.call(read.call("app/models/user.rb"), :display_name, "app/models/user.rb")
visible = select.call(read.call("app/models/topic.rb"), :visible_tags, "app/models/topic.rb")
append.call("app/models/topic_poster.rb", poster)
append.call("app/models/user.rb", user)
tag_source = read.call("app/models/tag.rb")
append.call("app/models/tag.rb", [:full_url, :slug_for_url].map { |name| select.call(tag_source, name, "app/models/tag.rb") }.join("\n"))
File.write(File.join(build, "original_list_body_models.rb"), "module OriginalBodyTopic\n#{visible}\nend\nmodule OriginalBodyPoster\n#{poster}\nend\nmodule OriginalBodyUser\n#{user}\nend\n")
# Current source-backed anonymous tag profile is empty, but the return must be
# the actual materialized Array (as original tags.select), not its AR relation.
topic_path = File.join(app, "app/models/topic.rb")
topic_input = File.read(topic_path)
old = 'def visible_tags(guardian); raise ArgumentError, "unsupported nonempty visible-tag serialization profile" unless tags.empty?; tags; end'
new = 'def visible_tags(guardian); raise ArgumentError, "unsupported nonempty visible-tag serialization profile" unless tags.empty?; tags.to_a; end'
raise "source tag profile changed" unless topic_input.include?(old)
File.write(topic_path, topic_input.sub(old, new))
File.write(File.join(app, "sig/list_body_reads.rbs"), "class SiteSetting\n  def self.enable_names?: () -> bool\n  def self.prioritize_username_in_ux?: () -> bool\nend\n")
template = read.call("app/views/list/list.erb")
compiled = ActionView::Template::Handlers::ERB::Erubi.new(template, escape: false, trim: true).src
body = "def render_list_body\n#{compiled}\nend\n"
# Fold only genuinely nil, runtime-checked /latest category/tag assignments.
false_predicates = ["@category", "@tag_name", "SiteSetting.tagging_enabled && @tag_name"]
else_source = nil
else_source = lambda do |node|
  return "nil" if node.nil?
  return node.statements&.slice || "nil" if node.is_a?(Prism::ElseNode)
  if node.is_a?(Prism::IfNode) && false_predicates.include?(node.predicate.slice)
    else_source.call(node.subsequent)
  else
    node.slice.sub(/\Aelsif\b/, "if")
  end
end
changes = []
walk = lambda do |node|
  if node.is_a?(Prism::IfNode) && false_predicates.include?(node.predicate.slice)
    replacement = else_source.call(node.subsequent)
    replacement = replacement.sub(/\Aif\b/, "elsif") if node.if_keyword_loc.slice == "elsif"
    changes << [node, replacement]
  else
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
end
walk.call(Prism.parse(body).value)
changes.sort_by { |node, _| -node.location.start_offset }.each { |node, text| body[node.location.start_offset, node.location.length] = text }
body = body.sub('I18n.l(t.last_posted_at || t.created_at, format: :date_only)', 'localize_list_date(t.last_posted_at || t.created_at)')
body = body.gsub('I18n.t(', 'list_translation(')
body = body.sub('Time.zone.now', 'ActiveSupport.present(Time.now)')
body = body.sub('t.excerpt.html_safe', 'trusted_list_html(t.excerpt)')
File.write(File.join(build, "body-lowering-diagnostic.rb"), body)
raise "invalid full list body lowering: #{Prism.parse(body).errors.map(&:message).join('; ')}" unless Prism.parse(body).success?
File.write(File.join(build, "native_list_body.rb"), "module NativeListBody\n#{body}\nend\n")
date_names = {}
%w[en fr].each do |locale|
  yaml = YAML.safe_load(read.call("config/locales/server.#{locale}.yml"), permitted_classes: [Symbol], aliases: true)
  names = yaml.fetch(locale).fetch("date")
  date_names[locale] = %w[day_names abbr_day_names month_names abbr_month_names].select { |name| names.key?(name) }.to_h { |name| ["date.#{name}", names.fetch(name)] }
end
names_path = File.join(app, "config/list_date_names.json")
File.write(names_path, JSON.generate(date_names))
proof[:date_names_resource] = {path: "config/list_date_names.json", sha256: Digest::SHA256.file(names_path).hexdigest, nil_month_zero_preserved: true, observed_payload: false}
# Original I18n localize/format implementations run with an explicit translation
# provider binding, not another global I18n bootstrap or captured localized date.
i18n_source, metadata = FidelitySourcePackage.member(root, "i18n-1.14.8", "lib/i18n/backend/base.rb")
proof[:framework] << metadata
localize = select.call(i18n_source, :localize, "i18n/backend/base.rb")
formatter = select.call(i18n_source, :translate_localization_format, "i18n/backend/base.rb")
File.write(File.join(build, "original_list_date.rb"), "module OriginalListDate\nEMPTY_HASH = {}.freeze\nclass Localizer\n#{localize}\n#{formatter}\nend\nend\n")
url_path = File.join(build, "native_category_cache_category_methods.rb")
url_source = File.read(url_path)
url_line = url_source.lines.find { |line| line.include?('cache.defer_get_set(id.to_s)') }
raise "native category URL observation anchor changed" unless url_line
url_source = url_source.sub(url_line, "    result = #{url_line.strip}\n    CategoryCacheBootstrap.lease.note_category_url(id.to_s, result)\n    result\n")
File.write(url_path, url_source)
proof[:native_body_sha256] = Digest::SHA256.hexdigest(body)
proof[:full_compiled_original_sha256] = Digest::SHA256.hexdigest(compiled)
proof[:transformations] = ["checked nil category/tag branch folding", "original anonymous empty tags return materialized Array", "date_only Time localization protocol binding", "explicit trusted excerpt wrapper; source trust preserved"]
File.write(File.join(build, "list-body-source-proof.json"), JSON.pretty_generate(proof) + "\n")
