# frozen_string_literal: true
# Experimental bounded Array capability, only in this run's generated tree.
# Never modifies the committed String capability or immutable source copies.
require "prism"
require "digest"
require "json"
require "open3"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, source: {}, array_cache_accepted: false, page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "Array source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
  proof[:source][path] = Digest::SHA256.hexdigest(source)
  source
end
File.write(File.join(app, "sig/theme_array_reads.rbs"), "class SiteSetting\n  def self.portable_rendering_asset_host: () -> String?\nend\n")
field = read.call("app/models/theme_field.rb")
cache = read.call("app/models/javascript_cache.rb")
theme = read.call("app/models/theme.rb")
# Exact actual targets declaration, never a guessed numeric target.
owner = Prism.parse(theme).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :targets }
call = method.body.body.first.value
raise "unknown Theme target declaration" unless call.name == :new && call.receiver.slice == "Enum"
targets = "{" + call.arguments.slice + "}"
File.write(File.join(app, "app/models/theme_field.rb"), "class ThemeField < ActiveRecord::Base\ndef ensure_baked!; raise 'unowned ThemeField PG bake refused before dispatch'; end\nend\n")
File.write(File.join(app, "app/models/javascript_cache.rb"), <<~RUBY)
  class JavascriptCache < ActiveRecord::Base
    def url
      "\#{SiteSetting.portable_rendering_asset_host}\#{Discourse.base_path}/theme-javascripts/\#{digest}.js?__ws=\#{Discourse.current_hostname}"
    end
  end
RUBY
# Source js_asset_info prefix/cache block; all applicable reads retained. A
# nonempty rebake set is a pre-dispatch safety refusal, NEVER skipped baking.
body = <<~RUBY
  module ListThemeCompilerSource
    def self.js_asset_info(theme_id, skip_transformation: false)
      return [] if ActiveSupport.blank?(theme_id)
      ids = !skip_transformation ? transform_ids(theme_id) : [theme_id]
      key = "\#{ids.join(',')}:extra_js:\#{compiler_version}"
      value = get_set_cache_assets(key) do
        target = #{targets}[:extra_js]
        rebake = ThemeField.where(theme_id: ids, target_id: target).where.not(compiler_version: compiler_version).to_a
        raise ArgumentError, 'unowned Theme asset rebake PG effects refused before dispatch' unless rebake.empty? && ENV.fetch("FIDELITY_ARRAY_FAULT", "") != "rebake-required"
        ActiveRecord::Base.transaction do
          rebake.each { |row| row.ensure_baked! }
          affected = Theme.where(id: rebake.map(&:theme_id)).to_a
          raise 'nonempty rebake theme set outside supported write-free profile' unless affected.empty?
        end
        by_theme = {}
        JavascriptCache.where(theme_id: ids).to_a.each { |row| by_theme[row.theme_id] = row }
        ids.map { |id| by_theme[id] }.compact.map do |row|
          {url: row.url, theme_id: row.theme_id, external_plugin_imports: row.external_plugin_imports}
        end
      end
      raise HtmlRenderingBoundary, 'actual Theme extra_js Array cache acquired; remaining import-map asset graph pending'
    end
    def self.get_set_cache_assets(key)
      cache = CategoryCacheBootstrap.theme_compiler_cache
      raise 'unbound concrete Array cache' unless cache.is_a?(CategoryCacheApplication::DistributedCache)
      cache.defer_get_set_assets(key) { yield }
    end
  end
RUBY
File.write(File.join(build, "native_theme_array_context.rb"), "module ListThemeArraySource\nTARGETS = #{targets}\nend\n" + body)
# Make exact storage type narrowing explicit rather than weakening String sites.
path = File.join(build, "category_cache_application_source.rb")
source = File.read(path)
source = source.sub('return self[k] if hash.key? k', 'if hash.key? k; hit = self[k]; raise TypeError, "non-String cache hit" unless hit.is_a?(String); return hit; end')
source = source.sub('    value = yield', '    value = yield; raise TypeError, "non-String cache computation" unless value.is_a?(String)')
source << <<~RUBY
  module CategoryCacheApplication
    class DistributedCache
      def defer_get_set_assets(key)
        raise TypeError, 'non-String Array cache key' unless key.is_a?(String)
        key = key.to_s
        @category_data_monitor.synchronize do
          if hash.key?(key)
            hit = self[key]
            raise TypeError, 'non-Array cache hit' unless hit.is_a?(Array)
            hit
          else
            value = yield
            raise TypeError, 'non-Array cache computation' unless value.is_a?(Array)
            CategoryCacheBootstrap.lease.note_theme_array(key, value)
            defer_set(key, value)
            value
          end
        end
      end
    end
  end
RUBY
File.write(path, source)
raise 'invalid typed Array projection' unless Prism.parse(source).success? && Prism.parse(body).success?
proof[:adaptations] = ["actual rebake rows materialized; nonempty set refuses before write methods", "actual JavascriptCache rows retain last-per-theme indexing and requested theme ordering", "String cache contract narrowed explicitly; separate Array getter on same source cache", "outgoing Marshal bytes must be registered from genuinely computed Array before publication"]
File.write(File.join(build, "theme-array-source-proof.json"), JSON.pretty_generate(proof) + "\n")
