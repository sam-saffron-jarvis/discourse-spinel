# frozen_string_literal: true
# Actual serializer read dependencies; specialize only explicitly excluded
# localization/auth profiles and remove distributed READ caches, never data.
require "prism"
require "json"
require "digest"
require "fileutils"
require "open3"
root = File.expand_path("../..", __dir__)
reference = File.join(root, "discourse")
candidate = File.join(root, "fidelity/compat/discourse")
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
lock_path = File.join(root, "fidelity/SOURCE_LOCK.json")
lock = JSON.parse(File.read(lock_path))
changes = []
inputs = {}
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", reference, "show", "#{pin}:#{path}")
  raise "missing pinned dependency #{path}" unless status.success?
  source = source.b
  raise "reference changed #{path}" unless source == File.binread(File.join(reference, path))
  sha = Digest::SHA256.hexdigest(source)
  inputs[path] = sha
  copied = File.join(root, "fidelity/source/discourse", path)
  if File.exist?(copied)
    raise "immutable copy changed #{path}" unless File.binread(copied) == source
  else
    FileUtils.mkdir_p(File.dirname(copied))
    File.binwrite(copied, source)
  end
  prior = lock["files"].find { |item| item["path"] == path }
  raise "source lock changed #{path}" if prior && prior["sha256"] != sha
  lock["files"] << {"path" => path, "sha256" => sha} unless prior
  source
end
write = lambda do |path, source, edits|
  text = source.dup
  edits.sort_by { |node, _, _| -node.location.start_offset }.each do |node, replacement, reason|
    text[node.location.start_offset, node.location.length] = replacement
    changes << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(node.slice), reason: reason}
  end
  raise "invalid dependency #{path}" unless Prism.parse(text).success?
  target = File.join(candidate, path)
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, text)
end
# Preserve true/false/nil from the original live-flag early exits. Enabled
# localization is refused, not a frozen false setting or fabricated translation.
path = "lib/content_localization.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
edits = []
%w[show_translated_topic? show_translated_tag? show_translated_category?].each do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |method| method.name.to_s == name }
  raise "localization source changed #{name}" unless node
  edits << [node, "def self.#{name}(object, scope)\n    enabled = SiteSetting.content_localization_enabled\n    raise ArgumentError, \"unsupported enabled localization serialization\" if enabled\n    enabled\n  end", "Guard enabled localization; return actual live false flag from original leading && clause"]
end
write.call(path, source, edits)
# Guardian uses the real AnonymousUser constructor/identity. Replace only the
# custom-blank protocol with explicit type checks for valid User/AnonymousUser;
# no fake member/permission object and no permission result map.
path = "lib/guardian.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
edits = []
{"user" => "def user\n    @user.is_a?(AnonymousUser) ? nil : @user\n  end",
 "authenticated?" => "def authenticated?\n    !@user.is_a?(AnonymousUser) && !@user.nil?\n  end"}.each do |name, replacement|
  node = owner.body.body.grep(Prism::DefNode).find { |method| method.name.to_s == name && method.receiver.nil? }
  raise "guardian identity source changed #{name}" unless node
  edits << [node, replacement, "Explicit valid-identity blank semantics, not a canned anonymous permission interface"]
end
create = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :can_create? }
raise "create permission source changed" unless create&.slice&.include?("return false unless authenticated? && klass")
edits << [create, 'def can_create?(klass, parent = nil); return false unless authenticated? && klass; raise ArgumentError, "unsupported authenticated create permission profile"; end', "Retain actual anonymous authentication early return; authenticated permission dispatcher explicitly refuses"]
anonymous = owner.body.body.grep(Prism::ClassNode).find { |node| node.constant_path.slice == "AnonymousUser" }
groups = anonymous.body.body.grep(Prism::DefNode).find { |method| method.name == :in_any_groups? }
raise "anonymous group permission source changed" unless groups
replacement = <<~RUBY.chomp
  def in_any_groups?(group_ids)
    return true if group_ids.include?(Group::AUTO_GROUPS[:anonymous_users])
    return false unless group_ids.include?(Group::AUTO_GROUPS[:everyone])
    !SiteSetting.granular_anonymous_and_logged_in_groups_permissions
  end
RUBY
# Keep the unchanged historical constructor/is_admin source-location checks.
replacement += "\n" * (groups.slice.count("\n") - replacement.count("\n"))
edits << [groups, replacement, "Boolean-equivalent permission evaluation skips upcoming flag only where both branches have the same result; everyone-only still reads/refuses real flag"]
tag_source = read.call("lib/guardian/tag_guardian.rb")
tag_owner = Prism.parse(tag_source).value.statements.body.grep(Prism::ModuleNode).first
pms = tag_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :can_tag_pms? }
see_tags = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :can_see_tags? }
raise "actual PM tag permission roots changed" unless pms && see_tags
edits << [see_tags, see_tags.slice.sub("topic.present?", "!topic.nil?") + "\n\n  " + pms.slice, "Ground actual inherited PM tagging method; real authenticated early return and group checks retained"]
write.call(path, source, edits)
# The complete fixed core declaration set comes from the pinned DB schema.
# Every accessor continues to resolve live selected theme rows.
path = "lib/theme_modifier_helper.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
macro = owner.body.body.grep(Prism::CallNode).find { |node| node.name == :each }
raise "theme modifier declaration changed" unless macro&.block
structure = read.call("db/structure.sql")
columns = structure.match(/^CREATE TABLE public\.theme_modifier_sets \(\n(.*?)^\);/m)
raise "theme modifier schema declaration changed" unless columns
names = columns[1].lines.filter_map { |line| line[/^    ([a-z_]+) /, 1] } - %w[id theme_id theme_setting_modifiers]
raise "empty theme modifier declarations" if names.empty?
replacement = names.map { |name| "def #{name}\n    Theme.lookup_modifier(@theme_ids, :#{name})\n  end" }.join("\n\n  ")
write.call(path, source, [[macro, replacement, "Expand actual fixed serializer demand roots; live Theme.lookup_modifier retained"]])
# Keep complete original theme source as the candidate, alter only read-cache
# wrappers, and retain actual parent/component/disabled/source-version logic.
path = "app/models/theme.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
names = %i[parent_theme_ids components_for transform_ids lookup_modifier theme_ids user_theme_ids allowed_remote_theme_ids]
edits = owner.body.body.grep(Prism::DefNode).filter_map do |method|
  next unless names.include?(method.name) && method.receiver
  calls = []
  walk = lambda do |node|
    calls << node if node.is_a?(Prism::CallNode) && node.name == :get_set_cache && node.block
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(method)
  raise "theme read cache changed #{method.name}" unless calls.length == 1
  node = calls.first
  [node, node.block.body.slice, "Fresh actual read instead of distributed cache; cache-effect equivalence not claimed"]
end
raise "theme read roots changed" unless edits.length == names.length
supported = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :supported? && method.receiver.nil? }
raise "theme supported-version source changed" unless supported
edits << [supported, 'def supported?; raise ArgumentError, "unsupported configured remote theme version constraints" if remote_theme&.minimum_discourse_version || remote_theme&.maximum_discourse_version; true; end', "Preserve original no-version-constraints true branch; configured version profiles explicitly refuse"]
allowed = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :allowed_remote_theme_ids }
raise "theme repository configuration source changed" unless allowed.slice.include?("GlobalSetting.allowed_theme_repos")
# Apply to the whole method in the existing edit to avoid overlapping spans.
# Its distributed-cache wrapper was selected above; the config reads lie
# outside and inside that wrapper, so add a separate whole-source pass below.
write.call(path, source, edits)
theme_path = File.join(candidate, path)
theme_text = File.read(theme_path).gsub("GlobalSetting.allowed_theme_repos", "SiteSetting.portable_allowed_theme_repos")
File.write(theme_path, theme_text)
changes << {source: path, start_byte: allowed.location.start_offset, end_byte: allowed.location.end_offset,
  text_sha256: Digest::SHA256.hexdigest(allowed.slice), reason: "Shared live allowed-theme-repositories accessor; native configuration and Rails GlobalSetting adapter, never captured permissions"}
# Native models expose catalog-driven columns, not Rails Column instances.
# Read the SAME live schema facts via the common readonly AR catalog adapter.
path = "app/models/theme_modifier_set.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
node = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :load_modifiers && method.receiver }
raise "theme modifier schema source changed" unless node
replacement = <<~RUBY.chomp
  def self.load_modifiers
    hash = {}
    rows = ActiveRecord::Base.connection.select_rows("SELECT column_name, data_type, udt_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theme_modifier_sets' ORDER BY ordinal_position")
    rows.each do |row|
      column_name = row[0]
      next if %w[id theme_id theme_setting_modifiers].include?(column_name)
      type = nil
      if row[1] == "ARRAY" && %w[_text _varchar].include?(row[2])
        type = :string_array
      elsif row[1] == "boolean"
        type = :boolean
      elsif !%w[text character\ varying].include?(row[1])
        raise ThemeModifierSetError, "Invalid theme modifier column type"
      end
      hash[column_name.to_sym] = {type: type}
    end
    hash
  end
RUBY
write.call(path, source, [[node, replacement, "Same source schema-derived modifier type metadata through readonly information_schema, never effective values"]])
path = "app/models/emoji.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
edits = []
%w[emojis tonable_emojis aliases].each do |name|
  node = methods.find { |method| method.name.to_s == "#{name}_db_file" }
  raise "emoji package-path getter changed #{name}" unless node
  edits << [node, "def self.#{name}_db_file\n    File.expand_path(\"../../config/portable_emoji_source/#{name}.json\", __dir__)\n  end", "Same verified published gem data from shared packaged resources; no observed Unicode/title inputs"]
end
node = methods.find { |method| method.name == :denied }
raise "emoji deny-list read changed" unless node
edits << [node, "def self.denied\n    load_denied\n  end", "Actual live deny-list read without distributed cache; effect/cache equivalence unclaimed"]
node = methods.find { |method| method.name == :replacement_code }
raise "emoji codepoint conversion source changed" unless node&.slice&.include?('code.split("-").map!(&:hex).pack("U*")')
edits << [node, node.slice.sub('map!(&:hex)', 'map { |part| part.hex }'), "Fresh split array has no aliases: nonmutating Integer map is equivalent and avoids native String-array map! element-type retention"]
node = methods.find { |method| method.name == :gsub_emoji_to_unicode }
raise "emoji code matcher changed" unless node
edits << [node, 'def self.gsub_emoji_to_unicode(str); str.gsub(EMOJI_CODE_REGEXP) { |name| Emoji.lookup_unicode(name[1...-1]) || name } if str; end', "Use actual matched token instead of unsupported global match-register lookup; same source regexp and Unicode resolver"]
write.call(path, source, edits)
path = "app/models/tag.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :topic_count_column && node.receiver }
raise "fixed tag count column convention changed" unless method && method.slice.scan(/\"staff_topic_count\"/).length == 1 && method.slice.scan(/\"public_topic_count\"/).length == 1
top = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :top_tags && node.receiver }
raise "top tag source signature changed" unless top
header = top.slice.lines.first.chomp
empty_top = header + "\n    return [] unless exists?\n    raise ArgumentError, \"unsupported nonempty top-tag serialization profile\"\n  end"
helper = <<~RUBY.chomp
  def self.topic_count_for(tag, guardian)
    column = topic_count_column(guardian)
    case column
    when "staff_topic_count"
      tag.staff_topic_count
    when "public_topic_count"
      tag.public_topic_count
    else
      raise ArgumentError, "unsupported tag count column"
    end
  end
RUBY
write.call(path, source, [[method, method.slice + "\n\n  " + helper, "Expand actual finite count-column dispatch to source-owned direct column reads, retaining live permission/setting selection"], [top, empty_top, "Actual empty-table early exit equals original empty join result; nonempty tag profile explicitly refuses, no frozen tag/setting values"]])
path = "app/models/user.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
edits = []
instance_avatar = methods.find { |method| method.name == :avatar_template && method.receiver.nil? }
static_avatar = methods.find { |method| method.name == :avatar_template && method.receiver }
default_avatar = methods.find { |method| method.name == :default_template && method.receiver }
raise "avatar read roots changed" unless instance_avatar && static_avatar && default_avatar
raise "avatar CDN source changed" unless instance_avatar.slice.include?('Discourse.store.cdn_url(SiteSetting.logo_small.url)')
edits << [instance_avatar, instance_avatar.slice.sub('Discourse.store.cdn_url(SiteSetting.logo_small.url)', 'SiteSetting.portable_avatar_cdn_url(SiteSetting.logo_small.url)'), "Retain real system/default/uploaded avatar branching and live Upload row; common actual configuration CDN guard"]
raise "avatar hostname source changed" unless static_avatar.slice.include?('RailsMultisite::ConnectionManagement.current_hostname')
edits << [static_avatar, static_avatar.slice.sub('RailsMultisite::ConnectionManagement.current_hostname', 'SiteSetting.portable_rendering_hostname'), "Real single-site hostname configuration through shared context; not a captured hostname"]
system_avatar = methods.find { |method| method.name == :system_avatar_template && method.receiver }
raise "system avatar fallback source changed" unless system_avatar
letter_source = read.call("lib/letter_avatar.rb")
raise "source avatar version declaration changed" unless letter_source.include?("VIPS_VERSION = 6")
replacement = system_avatar.slice.gsub('Discourse.base_path', 'SiteSetting.portable_rendering_base_path')
replacement = replacement.sub('Discourse.current_hostname', '(SiteSetting.force_hostname.presence || SiteSetting.portable_rendering_hostname)')
replacement = replacement.gsub('UrlHelper.encode_component', 'PortableAvatarEncoding.component')
replacement = replacement.sub('normalized_username = normalize_username(username)', 'normalized_username = normalize_username(username)' + "\n    raise ArgumentError, \"unsupported blank avatar username\" if normalized_username.nil?")
replacement = replacement.sub('LetterAvatar.version', 'PortableLetterAvatarVersion.version')
replacement = replacement.sub('normalized_username.grapheme_clusters.first', 'normalized_username[0]')
edits << [system_avatar, replacement, "Preserve complete real external/default avatar branching, live settings/color/URL encoding and runtime library/font fallback hash"]
system = methods.find { |method| method.name == :is_system_user? && method.receiver.nil? }
raise "system user identity source changed" unless system&.slice&.include?('Discourse::SYSTEM_USER_ID')
# Use the existing source declaration's actual identity constant in the common
# shared code; this is not a fabricated actor object or a privileged input.
read.call("lib/discourse.rb")
discourse_source = File.binread(File.join(reference, "lib/discourse.rb"))
constant = Prism.parse(discourse_source).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :SYSTEM_USER_ID }
raise "system user source identity declaration changed" unless constant && constant.value.slice == "-1"
edits << [system, system.slice.sub('Discourse::SYSTEM_USER_ID', constant.value.slice), "Ground actual source SYSTEM_USER_ID declaration; no runtime actor/session data frozen"]
color = methods.find { |method| method.name == :letter_avatar_color && method.receiver }
raise "avatar color source changed" unless color&.slice&.include?('LetterAvatar::COLORS')
edits << [color, color.slice.gsub('LetterAvatar::COLORS', 'PortableAvatarPalette::COLORS'), "Read same pinned source palette through ordinary shared constant, not cached production colors"]
letter_owner = Prism.parse(letter_source).value.statements.body.grep(Prism::ClassNode).first
palette = letter_owner.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :COLORS }
raise "source avatar palette changed" unless palette
palette_source = "# frozen_string_literal: true\nclass PortableAvatarPalette\n  " + palette.slice + "\nend\n"
File.write(File.join(candidate, "lib/portable_avatar_palette.rb"), palette_source)
normalizer = methods.find { |method| method.name == :normalize_username && method.receiver }
raise "avatar username normalization source changed" unless normalizer
edits << [normalizer, 'def self.normalize_username(username); raise ArgumentError, "unsupported non-ASCII avatar username normalization" if username && !username.to_s.ascii_only?; username.to_s.downcase if username.present?; end', "ASCII NFC is identity and its first character is its first grapheme; non-ASCII normalization explicitly refuses rather than pretending Unicode support"]
write.call(path, source, edits)
user_target = File.join(candidate, path)
user_candidate = File.binread(user_target)
user_candidate = user_candidate.sub("class User < ActiveRecord::Base", 'require_relative "../../lib/portable_letter_avatar_version"' + "\n" + 'require_relative "../../lib/portable_avatar_palette"' + "\n" + 'require_relative "../../lib/portable_avatar_encoding"' + "\n\nclass User < ActiveRecord::Base")
File.binwrite(user_target, user_candidate)
path = "app/models/user_avatar.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :local_avatar_template && node.receiver }
raise "avatar URL base source changed" unless method&.slice&.include?('Discourse.base_path')
write.call(path, source, [[method, method.slice.sub('Discourse.base_path', 'SiteSetting.portable_rendering_base_path'), "Same source avatar path with actual shared application base-path configuration"]])
path = "app/models/group.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :flair_url }
raise "flair image CDN source changed" unless method&.slice&.include?('upload_cdn_path(flair_upload.url)')
write.call(path, source, [[method, method.slice.sub('upload_cdn_path(flair_upload.url)', 'SiteSetting.portable_avatar_cdn_url(flair_upload.url)'), "Preserve icon/image/nil selection; common actual configuration CDN guard"]])
# Bind the shared single-site hostname reader to the ACTUAL development
# connection configuration, not the unrelated GlobalSetting.hostname default.
database_configuration = read.call("config/database.yml")
development_configuration = database_configuration.split("development:\n", 2).last&.split("\n# Warning:", 2)&.first
hostname_expression = "ENV['DISCOURSE_HOSTNAME'] || 'localhost'"
raise "development hostname source changed" unless development_configuration&.include?("- \"<%= #{hostname_expression} %>\"")
shared_configuration = File.read(File.join(candidate, "lib/site_settings/portable_global_configuration.rb"))
raise "shared database hostname expression changed" unless shared_configuration.include?(hostname_expression)
# Preserve originals needed by the read projections; no lifecycle execution.
%w[lib/pinned_check.rb lib/topic_subtype.rb app/models/child_theme.rb app/models/remote_theme.rb app/models/emoji.rb].each { |path| read.call(path) }
# Exact published assets are build inputs, not captured effective output.
# Recreate them from the separately package-verified/hash-locked originals.
framework_reads = {}
{
  "discourse-emojis-1.0.47/dist/emojis.json" => "config/portable_emoji_source/emojis.json",
  "discourse-emojis-1.0.47/dist/tonable_emojis.json" => "config/portable_emoji_source/tonable_emojis.json",
  "discourse-emojis-1.0.47/dist/aliases.json" => "config/portable_emoji_source/aliases.json",
  "discourse-fonts-0.0.19/vendor/assets/fonts/NotoSans-Regular.woff2" => "config/portable_avatar_source/NotoSans-Regular.woff2",
}.each do |source_name, target_name|
  source_path = "source/framework/" + source_name
  entry = lock.fetch("framework_sources").flat_map { |group| group.fetch("files") }.find { |item| item["path"] == source_path }
  bytes = File.binread(File.join(root, "fidelity", source_path))
  raise "framework resource changed #{source_path}" unless entry && Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256")
  target = File.join(candidate, target_name)
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, bytes)
  framework_reads[source_path] = entry.fetch("sha256")
end
uri_source = "source/framework/addressable-2.9.0/lib/addressable/uri.rb"
framework_reads[uri_source] = Digest::SHA256.file(File.join(root, "fidelity", uri_source)).hexdigest
File.write(lock_path, JSON.pretty_generate(lock) + "\n")
manifest = {profile: "Source-derived serializer read dependencies; not request acceptance", source_sha256: inputs,
  framework_read_sources: framework_reads,
  guarded_source_changes: changes, distributed_cache_equivalence_accepted: false, captured_effective_values: false,
  json_request_accepted: false, full_query_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/progressive/stage4/READ_DEPENDENCIES_MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
