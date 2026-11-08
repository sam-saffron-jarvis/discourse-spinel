# frozen_string_literal: true
module RequestMessageFormatCompiler
  def self.validate_source!
    lease = CategoryCacheBootstrap.lease
    lease.check!(lease.host, lease.port)
    root = ENV.fetch('FIDELITY_MF_SOURCE_ROOT')
    metadata = JSON.parse(File.read(File.join(root, 'source-lease.json')))
    raise ArgumentError, 'unowned MessageFormat source fixture' unless metadata['owner_pid'] == ENV.fetch('FIDELITY_CACHE_OWNER_PID').to_i && metadata['generated_result_supplied'] == false
    metadata['files'].each do |name, sha|
      raise ArgumentError, 'MessageFormat source member traversal' unless name.is_a?(String) && !name.start_with?('/') && !name.split('/').include?('..')
      raise ArgumentError, 'MessageFormat source member identity' unless Digest::SHA256.file(File.join(root, name)).hexdigest == sha
    end
    File.read(File.join(root, 'source-packet.json'))
  end
  def self.compile(locales, messages, strict: true)
    packet = validate_source!
    backend = LayoutAssetProcessorVM.backend
    raise 'actual original asset VM platform is not owned' unless backend.is_a?(LayoutAssetProcessorBackend)
    backend.compile_messageformat(packet, JSON.generate(locales), JSON.generate(messages), strict)
  end
end
class RequestClientLocaleSource
  def ensure_messageformat_compiler!; RequestMessageFormatCompiler.validate_source!; nil; end
  def compile_messageformat(locales, messages, strict: true)
    RequestMessageFormatCompiler.compile(locales, messages, strict: strict)
  end
  def log_messageformat_error(message)
    lease = CategoryCacheBootstrap.lease
    lease.check!(lease.host, lease.port)
    raise ArgumentError, 'unbounded MessageFormat error log' unless message.is_a?(String) && message.bytesize <= 1_048_576
    $stderr.puts('FIDELITY_OWNED_MESSAGEFORMAT_LOG ' + message)
  end
end
module RequestClientLocaleBootstrap
  class << self; attr_accessor :last_mf_script; attr_writer :mf_builds; end
  def self.mf_builds; @mf_builds ||= 0; end
  def self.build_mf(locale)
    RequestMessageFormatCompiler.validate_source!
    current_root = root
    raise 'client locale root is not bound' unless current_root.is_a?(String)
    helper = RequestClientLocaleSource.new(current_root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))
    result = helper.output_MF(locale)
    raise TypeError, 'MF locale output is not String' unless result.is_a?(String)
    self.last_mf_script = result
    self.mf_builds = mf_builds + 1
    result
  end
end
module MessageFormatViewProtocol
  def expected_body_events
    ['template_lookup', 'layout_lookup', 'view_flow_receiver', 'body_template', 'view_flow_set', 'layout_render', 'layout_head_partial', 'layout_color_cache_acquisition', 'layout_head_returned', 'layout_importmap_template', 'asset_serving_root_acquisition', 'theme_compiler_version_acquisition', 'layout_importmap_returned', 'locale_bundle_acquisition:main', 'locale_bundle_acquisition:mf', 'locale_bundle_acquisition:overrides']
  end
  def messageformat_stage_observation
    record = locale_stage_observation
    script = RequestClientLocaleBootstrap.last_mf_script
    raise 'MF client script was not acquired' unless script.is_a?(String) && !script.empty? && RequestClientLocaleBootstrap.mf_builds == 1
    digest = ExtraLocalesController.digest_for_content(script)
    raise 'genuine MF locale preload missing' unless controller.asset_preload_links.any? { |link| link.include?(digest) }
    record[:mf_locale] = {bytes: script.bytesize, sha256: Digest::SHA256.hexdigest(script), digest: digest, builds: RequestClientLocaleBootstrap.mf_builds}
    record
  end
end
class ListBodyContext
  include MessageFormatViewProtocol
  def observation; messageformat_stage_observation; end
end
