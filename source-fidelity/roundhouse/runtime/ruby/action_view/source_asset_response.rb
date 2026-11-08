# frozen_string_literal: true
require "uri"
module ActionView
  # Source-backed Propshaft::Server Rack method profile: genuine JS assets,
  # source-mapping-only compilation and pinned Rack 2 headers. Only explicit
  # Propshaft NullFileWatcher refresh is supported; no AS/evented watcher.
  # No Rack 3 header/profile support or listener/deployment is implied.
  class SourceAssetResponse
    def initialize(app, load_path, prefix, sweep_cache, watcher_profile = "none")
      if sweep_cache && watcher_profile != "null"
        raise ArgumentError, "unsupported asset cache watcher profile"
      end
      @refresh_each_call = sweep_cache
      @app = app
      @load_path = load_path
      @prefix = prefix
    end

    def call(env)
      # Propshaft's actual default NullFileWatcher invokes clear+seed under a
      # mutex on every call, including fallback/404. Real file-watchers remain
      # outside this explicit profile; they are never silently suppressed.
      @load_path.refresh! if @refresh_each_call
      path = env.fetch("PATH_INFO")
      method = env.fetch("REQUEST_METHOD")
      if (method == "GET" || method == "HEAD") && path.start_with?(@prefix)
        path = URI.decode_www_form_component(path.delete_prefix(@prefix))
        # The upstream digest regex explicitly excludes .digested at that
        # dot. A canonical .digested.js suffix therefore has no extracted
        # digest; avoid exponential backtracking on long genuine chunk names.
        digest = nil
        unless path.end_with?(".digested.js")
          digest = path[/-([0-9a-zA-Z]{7,128})\.(?!digested)([^.]|.map)+\z/, 1]
          path = path.sub("-#{digest}", "") if digest
        end
        asset = @load_path.find(path)
        if asset && asset.fresh?(digest)
          compiled_content = asset.compiled_content
          [200, {"Content-Length" => compiled_content.length.to_s,
                 "Content-Type" => asset.content_type_with_charset,
                 "Vary" => "Accept-Encoding", "ETag" => "\"#{asset.digest}\"",
                 "Cache-Control" => "public, max-age=31536000, immutable"},
           method == "HEAD" ? [] : [compiled_content]]
        else
          [404, {"Content-Type" => "text/plain", "Content-Length" => "9"}, ["Not found"]]
        end
      else
        @app.call(env)
      end
    end
  end
end
