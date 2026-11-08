# frozen_string_literal: true
require "prism"
require "json"
require "digest"
require "open3"
require "rubygems/package"
require "stringio"
require "zlib"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, application_sources: {}, framework_sources: {}, selected_spans: []}
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
  proof[:application_sources][path] = Digest::SHA256.hexdigest(source)
  source
end
source = read.call("app/helpers/application_helper.rb")
initializer = read.call("config/initializers/assets.rb")
raise "original compiler profile changed" unless initializer.include?('type == "text/javascript" && compiler == Propshaft::Compiler::SourceMappingUrls')
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
methods = %i[script_asset_path asset_cdn_path is_brotli_req?].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }
  raise "URL helper missing #{name}" unless node
  proof[:selected_spans] << {source: "app/helpers/application_helper.rb", method: name,
    start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
# Verify cached gem, locked checksum and each installed source against the
# package payload before using it as the original framework reference.
%w[propshaft-1.3.2 actionview-8.1.4 erubi-1.13.1 rack-2.2.24].each do |gem|
  archive = File.join(root, "run/bundle/ruby/4.0.0/cache/#{gem}.gem")
  hash = Digest::SHA256.file(archive).hexdigest
  lock = File.read(File.join(root, "discourse/Gemfile.lock"))
  name, version = gem.match(/\A(.+)-(\d[^-]*)\z/).captures
  raise "framework package checksum differs from lock" unless lock.include?("#{name} (#{version}) sha256=#{hash}")
  package = Gem::Package.new(archive)
  package.verify
  members = {}
  package.contents.grep(/lib\/.*\.rb\z/).each { |path| members[path] = nil }
  File.open(archive, "rb") do |io|
    Gem::Package::TarReader.new(io) do |tar|
      tar.each do |entry|
        next unless entry.full_name == "data.tar.gz"
        Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(entry.read))) do |data|
          data.each do |item|
            next unless members.key?(item.full_name)
            installed = File.join(root, "run/bundle/ruby/4.0.0/gems/#{gem}", item.full_name)
            bytes = item.read
            raise "installed framework changed #{gem}/#{item.full_name}" unless File.binread(installed) == bytes
            members[item.full_name] = Digest::SHA256.hexdigest(bytes)
          end
        end
      end
    end
  end
  raise "unverified framework member" if members.values.any?(&:nil?)
  proof[:framework_sources][gem] = {package_sha256: hash, files: members}
end
{
  "propshaft-1.3.2/lib/propshaft/asset.rb" => %i[initialize content compiled_content content_type_with_charset digest digested_path fresh? content_with_compile_references already_digested?],
  "propshaft-1.3.2/lib/propshaft/server.rb" => %i[initialize call extract_path_and_digest execute_cache_sweeper_if_updated],
  "propshaft-1.3.2/lib/propshaft/load_path.rb" => %i[initialize execute_if_updated find assets_by_path all_files_from_tree without_dotfiles dedup cache_sweeper clear_cache seed_cache],
  "propshaft-1.3.2/lib/propshaft/resolver/dynamic.rb" => %i[initialize resolve find_asset],
  "propshaft-1.3.2/lib/propshaft/compiler.rb" => %i[referenced_by],
  "propshaft-1.3.2/lib/propshaft/errors.rb" => %i[initialize message],
  "actionview-8.1.4/lib/action_view/helpers/asset_url_helper.rb" => %i[asset_path compute_asset_extname compute_asset_host],
}.each do |path, names|
  tree = Prism.parse_file(File.join(root, "run/bundle/ruby/4.0.0/gems", path)).value
  visit = lambda do |node|
    if node.is_a?(Prism::DefNode) && names.include?(node.name)
      proof[:selected_spans] << {source: path, method: node.name,
        start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
    end
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(tree)
end
lowered = methods.map do |text|
  text = text.gsub("ActionController::Base.helpers", "asset_paths")
  text = text.gsub("ActionController::Base.config.relative_url_root", "settings.relative_url_root")
  text = text.gsub("GlobalSetting.", "settings.")
  text = text.sub('settings.s3_asset_cdn_url.presence', '(PortableResponseMiddlewareDeclarations.blank_header?(settings.s3_asset_cdn_url) ? nil : settings.s3_asset_cdn_url)')
  text
end
header = "# frozen_string_literal: true\n# GENERATED source-backed URL helpers; settings are explicit supplied unit inputs.\n"
original = header + "module PortableAssetUrlMethods\n#{methods.join("\n\n")}\nend\n"
candidate = header + "module PortableAssetUrlMethods\n#{lowered.join("\n\n")}\nend\n"
raise "invalid lowered URL helper" unless Prism.parse(candidate).success?
File.write(ARGV.fetch(0), original)
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_asset_urls.rb"), candidate)
proof[:candidate_sha256] = Digest::SHA256.hexdigest(candidate)
proof[:runtime_sha256] = Digest::SHA256.file(File.join(root, "roundhouse/runtime/ruby/action_view/source_asset_paths.rb")).hexdigest
proof[:runtime_signature_sha256] = Digest::SHA256.file(File.join(root, "roundhouse/runtime/ruby/action_view/source_asset_paths.rbs")).hexdigest
proof[:transformations] = ["Explicit settings/asset_paths replace unit original global contexts",
  "Existing fast_blank string/null header adapter for s3_asset_cdn_url.presence",
  "Framework native profile converts Pathname to String; retains file discovery/root precedence, original SHA1 bytes+version, digested-path regex and dynamic resolver",
  "Native directory recursion uses typed Dir.entries excluding dot/dotdot, equivalent to Pathname.children; typed digest insertion uses whole-match replacement with an extension guard (retains lazy digest acquisition)",
  "Original Discourse only registers SourceMappingUrls: referenced_by inherits empty Set, so no reference-content omission in this URL-only profile",
  "Rails asset_path specialized to no options and fixed HTTP(S)/protocol-relative host; host sharding/procs refuse"]
proof[:context] = "Unit settings/hosts/root/version, genuine files and actual original Propshaft resolver; NOT production configuration or a request"
proof.merge!(original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false)
File.write(File.join(root, "fidelity/compat/discourse/portable_asset_urls.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated verified source-backed URL helper and framework provenance"
