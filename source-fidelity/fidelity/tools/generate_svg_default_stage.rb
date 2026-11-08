# frozen_string_literal: true
require 'yaml'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:config/site_settings.yml")
raise 'SVG default declarations changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/config/site_settings.yml'))
settings = YAML.safe_load(source, aliases: true).values.reduce({}, :merge)
names = %w[whispers_allowed_groups pending_users_reminder_delay_minutes]
changes = names.to_h { |name| [name, settings.fetch(name).fetch('upcoming_change_default_override').fetch('upcoming_change')] }
File.write(File.join(build, 'svg_default_declarations.rb'), "module SvgDefaultDeclarations\nCHANGES = #{changes.inspect}\nend\n")
File.write(File.join(build, 'svg-default-source-proof.json'), JSON.pretty_generate({pin: pin, declarations_sha256: Digest::SHA256.hexdigest(source), names: names, changes: changes, source_semantics: ['Existing original UpcomingChanges.enabled? opt-out/status/promotion/default with no plugin/dependencies', 'Original SiteSettingExtension.refresh target modified exemption and override activation loop', 'Raw original DefaultsProvider.all activation and current modified precedence in third reference'], full_settings_boot: false, permission_maps_acquired: false, page_accepted: false}) + "\n")
