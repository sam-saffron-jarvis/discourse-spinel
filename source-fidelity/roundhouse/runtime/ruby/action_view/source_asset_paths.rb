# frozen_string_literal: true
require "digest/sha1"
require "thread"

module Propshaft
  class Error < StandardError; end
  class MissingAssetError < Error
    def initialize(path)
      super(path)
      @path = path
    end

    def message
      "The asset '#{@path}' was not found in the load path."
    end
  end
end

module ActionView
  # Read-only Propshaft dynamic lookup for the source-mapping-only compiler
  # profile. That compiler inherits Compiler#referenced_by's empty Set; URL
  # digests therefore use source bytes + version, never fabricated metadata.
  # No nonidentity compilation, integrity or evented/AS watcher is provided.
  # The response component can explicitly select Propshaft's default null watcher.
  class SourceAsset
    attr_reader :path, :logical_path

    def initialize(path, logical_path, version)
      @path = path
      @logical_path = logical_path
      @version = version
      @digest = nil
      @compiled_content = nil
    end

    def content
      File.binread(path)
    end

    def compiled_content
      return @compiled_content unless @compiled_content.nil?
      source = content
      # Pinned Discourse skips SourceMappingUrls for .digested. assets. For
      # plain JS without a sourcemap directive the actual compiler is identity.
      # Nonidentity compilation is not silently omitted by this profile.
      if !logical_path.include?(".digested.") && source.include?("sourceMappingURL=") && source.match?(%r{(//|/\*)# sourceMappingURL=(.+\.map)(\s*?\*/)?\s*?\Z})
        raise ArgumentError, "unsupported nonidentity source-map compilation profile"
      end
      @compiled_content = source
      source
    end

    def content_type_with_charset
      raise ArgumentError, "unsupported non-JavaScript asset response profile" unless logical_path.end_with?(".js")
      "text/javascript"
    end

    def fresh?(digest)
      self.digest == digest || already_digested?
    end

    def digest
      @digest ||= Digest::SHA1.hexdigest("#{content}#{@version}")[0, 8].to_s
    end

    def digested_path
      if already_digested?
        logical_path
      elsif logical_path.match?(/\.(\w+(\.map)?)$/)
        logical_path.sub(/\.(\w+(\.map)?)$/, "-#{digest}\\0")
      else
        logical_path
      end
    end

    def already_digested?
      logical_path.match?(/-([0-9a-zA-Z_-]{7,128})\.digested/)
    end
  end

  class SourceAssetLoadPath
    attr_reader :paths, :version

    def initialize(paths, version)
      @paths = dedup(paths.map { |path| File.expand_path(path) })
      @version = version
      @cached_assets = nil
      @refresh_mutex = nil
    end

    def refresh!
      mutex = @refresh_mutex ||= Mutex.new
      mutex.synchronize do
        @cached_assets = nil
        assets_by_path
      end
      nil
    end

    def find(asset_name)
      assets_by_path[asset_name]
    end

    def assets_by_path
      return @cached_assets unless @cached_assets.nil?
      mapped = {}
      paths.each do |path|
        if File.exist?(path)
          all_files_from_tree(path).each do |file|
            next if File.basename(file).start_with?(".")
            logical_path = file.delete_prefix(path + "/")
            mapped[logical_path] ||= SourceAsset.new(file, logical_path, version)
          end
        end
      end
      @cached_assets = mapped
      mapped
    end

    def all_files_from_tree(path)
      files = []
      names = Dir.entries(path)
      index = 0
      while index < names.length
        child = names[index].to_s
        index += 1
        next if child == "." || child == ".."
        full = File.join(path, child)
        if File.directory?(full)
          files.concat(all_files_from_tree(full))
        else
          files << full
        end
      end
      files
    end

    # Propshaft deliberately uses textual prefix deduplication here, not a
    # path-component prefix. Preserve its actual root order/precedence.
    def dedup(paths)
      deduped = []
      paths.sort.each do |path|
        last = deduped.last
        deduped << path if last.nil? || !path.start_with?(last)
      end
      paths.select { |path| deduped.include?(path) }.uniq
    end
  end

  class SourceAssetResolver
    attr_reader :load_path, :prefix

    def initialize(load_path, prefix)
      @load_path = load_path
      @prefix = prefix
    end

    def resolve(logical_path)
      if asset = load_path.find(logical_path)
        File.join(prefix, asset.digested_path)
      end
    end
  end

  class SourceAssetPaths
    def initialize(resolver, relative_url_root, asset_host)
      # The original compute_asset_host also supports procs, host sharding and
      # request-dependent protocols. Those are NOT this explicit fixed-host
      # profile. Refuse rather than return an invented equivalent URL.
      if asset_host && !asset_host.match?(%r{\A(?:https?:)?//[^%]+\z})
        raise ArgumentError, "unsupported fixed asset host profile"
      end
      @resolver = resolver
      @relative_url_root = relative_url_root
      @asset_host = asset_host
    end

    def asset_path(source)
      return "" if source.match?(/\A[\x00\x09-\x0d\x20]*\z/)
      return source if source.match?(%r{^[-a-z]+://|^(?:cid|data):|^//}i)
      tail = source[/([?#].+)$/, 1]
      source = source.sub(/([?#].+)$/, "")
      unless source.start_with?("/")
        resolved = @resolver.resolve(source)
        raise Propshaft::MissingAssetError.new(source) unless resolved
        source = resolved
      end
      root = @relative_url_root
      if root
        source = File.join(root, source) unless source.start_with?("#{root}/")
      end
      host = @asset_host
      source = File.join(host, source) if host
      "#{source}#{tail}"
    end
  end
end
