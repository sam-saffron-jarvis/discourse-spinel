# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'yaml'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, enum_classes: [], full_settings_boot: false, page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG enum source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
base = read.call('lib/enum_site_setting.rb')
base_owner = Prism.parse(base).value.statements.body.grep(Prism::ClassNode).first
raise 'enum base gained activation' unless base_owner.body.body.all? { |n| n.is_a?(Prism::DefNode) && n.receiver.is_a?(Prism::SelfNode) && %i[translate_names? wrap_values!].include?(n.name) }
settings = YAML.safe_load(read.call('config/site_settings.yml'), aliases: true).values.reduce({}, :merge)
names = {'desktop_category_page_style' => ['CategoryPageStyle', 'app/models/category_page_style.rb'], 'mobile_category_page_style' => ['MobileCategoryPageStyle', 'app/models/mobile_category_page_style.rb'], 'interface_color_selector' => ['InterfaceColorSelectorSetting', 'app/models/interface_color_selector_setting.rb']}
if ARGV[1]
  raise 'unsupported extra SVG enum profile' unless %w[full-name notice-enums media-enums review-enums utility-enums preference-enums].include?(ARGV[1])
  names['full_name_requirement'] = ['FullNameRequirement', 'app/models/full_name_requirement.rb']
  if %w[notice-enums media-enums review-enums utility-enums preference-enums].include?(ARGV[1])
    names['emoji_set'] = ['EmojiSetSiteSetting', 'app/models/emoji_set_site_setting.rb']
    settings.each do |name, declaration|
      names[name] = ['TrustLevelSetting', 'app/models/trust_level_setting.rb'] if declaration.is_a?(Hash) && declaration['enum'] == 'TrustLevelSetting'
    end
  end
end
if %w[media-enums review-enums utility-enums preference-enums].include?(ARGV[1])
  names['s3_region'] = ['S3RegionSiteSetting', 'app/models/s3_region_site_setting.rb']
  names['image_quality'] = ['ImageQualitySetting', 'app/models/image_quality_setting.rb']
end
if %w[review-enums utility-enums preference-enums].include?(ARGV[1])
  settings.each do |name, declaration|
    next unless declaration.is_a?(Hash)
    case declaration['enum']
    when 'ReviewableSensitivitySetting'
      names[name] = ['ReviewableSensitivitySetting', 'app/models/reviewable_sensitivity_setting.rb']
    when 'ReviewablePrioritySetting'
      names[name] = ['ReviewablePrioritySetting', 'app/models/reviewable_priority_setting.rb']
    end
  end
end
if %w[utility-enums preference-enums].include?(ARGV[1])
  utility_classes = {
    'NavigationMenuSiteSetting' => 'app/models/navigation_menu_site_setting.rb',
    'BackupLocationSiteSetting' => 'app/models/backup_location_site_setting.rb',
    'SearchSortOrderSiteSetting' => 'app/models/search_sort_order_site_setting.rb',
    'SearchExperienceSiteSetting' => 'app/models/search_experience_site_setting.rb',
    'SlugSetting' => 'app/models/slug_setting.rb',
  }
  settings.each do |name, declaration|
    next unless declaration.is_a?(Hash)
    klass = declaration['enum']
    names[name] = [klass, utility_classes[klass]] if utility_classes.key?(klass)
  end
end
if ARGV[1] == 'preference-enums'
  preference_classes = {
    'WelcomeBannerLocation' => 'welcome_banner_location',
    'WelcomeBannerPageVisibility' => 'welcome_banner_page_visibility',
    'DigestEmailSiteSetting' => 'digest_email_site_setting',
    'EmailLevelSiteSetting' => 'email_level_site_setting',
    'MailingListModeSiteSetting' => 'mailing_list_mode_site_setting',
    'PreviousRepliesSiteSetting' => 'previous_replies_site_setting',
    'NewTopicDurationSiteSetting' => 'new_topic_duration_site_setting',
    'AutoTrackDurationSiteSetting' => 'auto_track_duration_site_setting',
    'NotificationLevelWhenReplyingSiteSetting' => 'notification_level_when_replying_site_setting',
    'LikeNotificationFrequencySiteSetting' => 'like_notification_frequency_site_setting',
    'CompositionModeSiteSetting' => 'composition_mode_site_setting',
    'McpOauthClientIdMetadataPolicy' => 'mcp_oauth_client_id_metadata_policy',
  }
  settings.each do |name, declaration|
    next unless declaration.is_a?(Hash)
    klass = declaration['enum']
    names[name] = [klass, 'app/models/' + preference_classes[klass] + '.rb'] if preference_classes.key?(klass)
  end
end
pure_literal = lambda do |node|
  node.is_a?(Prism::StringNode) || (node.is_a?(Prism::ArrayNode) && node.elements.all? { |item| item.is_a?(Prism::StringNode) })
end
classes = names.map do |name, (klass, path)|
  raise 'SVG enum declaration changed' unless settings.fetch(name).fetch('enum') == klass
  text = read.call(path)
  owner = Prism.parse(text).value.statements.body.grep(Prism::ClassNode).first
  raise "SVG enum owner changed #{name}" unless owner.constant_path.slice == klass && owner.superclass.slice == 'EnumSiteSetting'
  allowed_methods = %i[valid_value? values translate_names? enabled? valid_values translation value_from_id id_from_value notification_levels]
  raise "SVG enum gained wrap/activation #{name}" unless owner.body.body.all? do |n|
    (n.is_a?(Prism::DefNode) && n.receiver.is_a?(Prism::SelfNode) && allowed_methods.include?(n.name)) ||
      (n.is_a?(Prism::ConstantWriteNode) && pure_literal.call(n.value)) ||
      (n.is_a?(Prism::CallNode) && n.name == :private_class_method && n.arguments.arguments.all? { |arg| arg.is_a?(Prism::SymbolNode) && %w[valid_values translation].include?(arg.unescaped) })
  end
  proof[:enum_classes] << {setting: name, class: klass, span_sha256: Digest::SHA256.hexdigest(owner.slice), wrap_activation_present: false, expected_return_class: settings.fetch(name).fetch('default').is_a?(Integer) ? 'Integer' : 'String'}
  owner.slice
end
File.write(File.join(build, 'svg_enum_declarations.rb'), "module SvgEnumDeclarations\nNAMES = #{names.transform_values(&:first).inspect}\nRETURN_CLASSES = #{names.to_h { |name, _| [name, settings.fetch(name).fetch('default').is_a?(Integer) ? 'Integer' : 'String'] }.inspect}\nend\n")
File.write(File.join(build, 'original_svg_enum_source.rb'), "module OriginalSvgEnumSource\n#{base_owner.slice}\n#{classes.uniq.join("\n")}\nCLASSES = {#{names.map { |name, (klass, _)| "#{name.dump} => #{klass}" }.join(', ')}}\nend\n")
proof[:transformations] = ['Only explicitly selected source enum family with proven class/base absence of wrap activation', 'Read values through actual live shared provider/default coercion; String or Integer matches source default-type enum ABI (no captured values)', 'Original TypeSupervisor metadata view recognizes implicit enum option even without explicit type: enum and returns actual pinned class', 'Raw original setup_methods checks actual klass.respond_to?(:wrap), no fabricated nil enum class', 'Whole settings initialization and all other named/wrapped enums remain unacquired']
File.write(File.join(build, 'svg-enum-source-proof.json'), JSON.pretty_generate(proof) + "\n")
