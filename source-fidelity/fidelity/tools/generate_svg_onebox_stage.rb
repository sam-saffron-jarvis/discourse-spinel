# frozen_string_literal: true
# Scoped class/read capability, never locale UI activation or a Onebox client.
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], full_settings_boot: false, page_accepted: false}
read = lambda do |path|
  bytes, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "Onebox source changed #{path}" unless status.success? && bytes.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(bytes)
  bytes
end
owners = {}
%w[lib/enum_site_setting.rb app/models/locale_site_setting.rb app/models/onebox_locale_site_setting.rb].each do |path|
  source = read.call(path)
  owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
  raise "Onebox class missing #{path}" unless owner
  owners[owner.constant_path.slice] = owner
  proof[:spans] << {path: path, class: owner.constant_path.slice, start: owner.location.start_offset, end: owner.location.end_offset, sha256: Digest::SHA256.hexdigest(owner.slice)}
end
base = owners.fetch('EnumSiteSetting')
locale = owners.fetch('LocaleSiteSetting')
onebox = owners.fetch('OneboxLocaleSiteSetting')
raise 'Onebox inheritance changed' unless locale.superclass.slice == 'EnumSiteSetting' && onebox.superclass.slice == 'LocaleSiteSetting'
raise 'Enum base gained activation' unless base.body.body.all? { |n| n.is_a?(Prism::DefNode) && n.receiver.is_a?(Prism::SelfNode) && %i[translate_names? wrap_values!].include?(n.name) }
locale_methods = %i[translate_names? valid_value? values language_names supported_locales reset! fallback_locale]
[locale, onebox].each do |owner|
  allowed = owner == locale ? locale_methods : [:valid_value?]
  raise 'Locale hierarchy gained wrap/activation' unless owner.body.body.all? do |node|
    (node.is_a?(Prism::DefNode) && node.receiver.is_a?(Prism::SelfNode) && allowed.include?(node.name)) ||
      (node.is_a?(Prism::InstanceVariableWriteNode) && node.name == :@lock && node.value.slice == 'Mutex.new') ||
      (owner == locale && node.is_a?(Prism::ConstantWriteNode) && node.name == :FALLBACKS)
  end
  locks = owner.body.body.grep(Prism::InstanceVariableWriteNode).select { |n| n.name == :@lock }
  raise 'Onebox per-class Mutex declaration changed' unless locks.size == 1
end
select = lambda do |owner, name|
  owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }.slice
end
lock = locale.body.body.grep(Prism::InstanceVariableWriteNode).first.slice
child_lock = onebox.body.body.grep(Prism::InstanceVariableWriteNode).first.slice
# Actual source constructor/metadata/inheritance only. Unacquired UI entrypoints
# refuse, rather than being replaced by empty locale tables or fake validators.
File.write(File.join(build, 'svg_onebox_classes.rb'), <<~RUBY)
  module SvgOneboxReadClasses
    class ReadEnumClass
      #{select.call(base, :translate_names?)}
    end
    class ReadLocaleClass < ReadEnumClass
      #{lock}
      #{select.call(locale, :translate_names?)}
      def self.read_lock; @lock; end
      def self.valid_value?(value); raise ArgumentError, 'locale UI validation unacquired'; end
      def self.values; raise ArgumentError, 'locale UI values unacquired'; end
      def self.supported_locales; raise ArgumentError, 'locale language scanning unacquired'; end
      def self.language_names; raise ArgumentError, 'locale language loading unacquired'; end
    end
    class ReadOneboxClass < ReadLocaleClass
      #{child_lock}
      def self.valid_value?(value); raise ArgumentError, 'Onebox locale UI validation unacquired'; end
    end
    # TEST-only wrong profile, never selected for production reads.
    class WrappedMutation < ReadLocaleClass
      def self.wrap(value); value; end
    end
  end
  module SvgOneboxSourceMembers
    HASHES = #{proof[:sources].inspect}
  end
RUBY
File.write(File.join(build, 'original_svg_onebox_classes.rb'), "module OriginalSvgOneboxClasses\n#{base.slice}\n#{locale.slice}\n#{onebox.slice}\nend\n")
read.call('lib/site_settings/type_supervisor.rb')
read.call('lib/site_setting_extension.rb')
read.call('config/site_settings.yml')
proof[:transformations] = ['Actual Locale/Onebox read-role hierarchy under explicit unique ReadEnumClass/ReadLocaleClass/ReadOneboxClass aliases, separate source Mutex.new allocations and inherited source metadata; no wrap activation', 'Native/shared class capability excludes unsupported UI bodies with explicit refusal; original loads complete pinned classes without calling UI validation/values/file scanners', 'Exact onebox_locale explicit enum declaration and String default/coercion; original TypeSupervisor metadata precedence/raw setup_methods checks actual original class', 'Actual live current getter read with source nil-refresh, no fabricated locale value; source String type/freeze/identity preserved', 'Source member provenance validated on existing owned serving lease before getter; no Onebox or locale scan/network']
File.write(File.join(build, 'svg-onebox-source-proof.json'), JSON.pretty_generate(proof) + "\n")
