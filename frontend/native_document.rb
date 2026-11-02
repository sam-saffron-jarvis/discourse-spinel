# frozen_string_literal: true

# Source-derived native /latest HTML bootstrap. Pure Ruby: no Rails, templates, or data
# capture. Topic mode accepts { id:, slug:, title: } and requires the corresponding
# JSON-text topic_<id> preload produced from TopicViewSerializer. The native server
# may port this contract; preloads/settings remain backend-owned.
require "cgi"
require "digest"
require "json"
require "uri"
require "erb"

class NativeDocument
  DEFAULT_STAGE_MANIFEST = File.expand_path("../build/assets/native/manifest.json", __dir__)

  def initialize(base_uri, manifest_path: DEFAULT_STAGE_MANIFEST)
    @base_uri = normalize_base_uri(base_uri)
    @manifest_path = manifest_path
  end

  def render(preloads, settings_hash, origin, topic: nil)
    descriptor = JSON.parse(File.read(@manifest_path))
    origin = normalize_origin(origin)
    settings = settings_hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
    topic = normalize_topic(topic, preloads) if topic
    default_locale = settings.fetch("default_locale", "en").to_s
    setup = {
      "base_url" => "#{origin}#{@base_uri}",
      "base_uri" => @base_uri,
      "environment" => "production",
      "default_locale" => default_locale,
      "asset_version" => "minimal-#{Digest::SHA1.hexdigest(File.read(@manifest_path))[0, 12]}",
      "service_worker_url" => "service-worker.js",
      "letter_avatar_version" => "5",
      "svg_sprite_path" => prefixed(descriptor.fetch("icons").fetch("sprite_url")),
      "disable_custom_css" => false,
      "color_scheme_is_dark" => false,
      "user_color_scheme_id" => -1,
      "user_dark_scheme_id" => -1,
      "is_staff" => false,
      "enable_js_error_reporting" => false,
    }

    preloaded = preloads.each_with_object({}) do |(key, value), output|
      raise ArgumentError, "preload #{key.inspect} must be JSON text" unless value.is_a?(String)
      JSON.parse(value)
      output[key.to_s] = value.gsub(/<\/?script/i) { |tag| tag.gsub("<", "\\u003c").gsub(">", "\\u003e") }
    end

    core = descriptor.fetch("core_ember")
    entrypoint = core.fetch("entrypoints").fetch("discourse")
    environment_config = {
      "modulePrefix" => "discourse",
      "environment" => "production",
      "rootURL" => @base_uri,
      "locationType" => "history",
      "EmberENV" => { "FEATURES" => {}, "EXTEND_PROTOTYPES" => false },
      "APP" => {
        "name" => "discourse",
        "version" => "#{descriptor.fetch("source").fetch("discourse_version")} #{descriptor.fetch("source").fetch("discourse_commit")}",
      },
    }
    encoded_environment = ERB::Util.url_encode(JSON.generate(environment_config))
    import_map = core.fetch("importMap").each_with_object({}) do |(stable, real), imports|
      # ApplicationHelper#generate_import_map keys the stable URL that a chunk's
      # relative import resolves to, not a bare package name.
      stable_url = core_asset(real).sub(File.basename(real), File.basename(stable))
      imports[stable_url] = core_asset(real)
    end
    # A reverse-connected Hub admits only a bounded number of requests. Do not
    # eagerly fan out the entire Ember graph: preload dependencies before their
    # parents, one request at a time, then evaluate the original entrypoint.
    plugins = []
    if settings["discourse_reactions_enabled"] == true
      descriptor.fetch("plugins", []).each do |plugin|
        plugins << {
          "name" => plugin.fetch("name"),
          "entry" => prefixed(plugin.fetch("entry")),
          "modules" => plugin.fetch("modules").map { |path| prefixed(path) },
        }
      end
    end
    boot_assets = safe_script_json(
      "modules" => dependency_files(entrypoint, core.fetch("chunks")).map { |filename| core_asset(filename) },
      "plugins" => plugins,
      "locale" => prefixed(descriptor.fetch("locale").fetch("url")),
      "entry" => core_asset(entrypoint),
    )

    css_links = descriptor.fetch("css").values.map do |asset|
      %(<link rel="stylesheet" href="#{attr(prefixed(asset.fetch("url")))}">)
    end.join("\n")
    scripts = descriptor.fetch("browser_scripts")
    locale_url = prefixed(descriptor.fetch("locale").fetch("url"))
    icon_url = prefixed(descriptor.fetch("icons").fetch("sprite_url"))
    setup["svg_sprite_path"] = icon_url

    setup_attributes = setup.map do |key, value|
      next if value.nil?
      %Q( data-#{key.tr("_", "-")}="#{attr(attribute_value(value))}")
    end.compact.join

    import_map_json = safe_script_json("imports" => import_map)
    preloaded_json = safe_script_json(preloaded)
    detect_url = prefixed(scripts.fetch("browser-detect").fetch("url"))
    update_url = prefixed(scripts.fetch("browser-update").fetch("url"))
    favicon = prefixed(descriptor.fetch("images").fetch("default-favicon.png").fetch("url"))

    <<~HTML
      <!DOCTYPE html>
      <html lang="#{attr(setup.fetch("default_locale", "en").tr("_", "-"))}" class="text-size-normal anon">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{topic ? "#{attr(topic.fetch("title"))} - #{attr(settings.fetch("title", "Discourse"))}" : "Latest topics - #{attr(settings.fetch("title", "Discourse"))}"}</title>
      <meta name="generator" content="Discourse #{attr(descriptor.fetch("source").fetch("discourse_version"))} - https://github.com/discourse/discourse version #{attr(descriptor.fetch("source").fetch("discourse_commit"))}">
      <meta name="discourse_theme_id" content="-1">
      #{topic ? %(<link rel="canonical" href="#{attr("#{origin}#{@base_uri}/t/#{topic.fetch("slug")}/#{topic.fetch("id")}")}">) : %(<meta name="discourse_current_homepage" content="latest">)}
      <link rel="icon" href="#{attr(favicon)}">
      <script type="importmap">#{import_map_json}</script>
      <script type="application/json" id="native-boot-assets">#{boot_assets}</script>
      <script defer src="#{attr(detect_url)}"></script>
      <script type="module" src="#{attr(locale_url)}"></script>
      <meta id="data-discourse-setup"#{setup_attributes}>
      <meta name="discourse-base-uri" content="#{attr(@base_uri)}">
      <meta name="discourse/config/environment" content="#{attr(encoded_environment)}">
      </head>
      <body>
      <discourse-assets>
        <discourse-assets-stylesheets>
      #{css_links}
        </discourse-assets-stylesheets>
        <discourse-assets-json><script type="application/json" id="data-preloaded">#{preloaded_json}</script></discourse-assets-json>
        <discourse-assets-icons></discourse-assets-icons>
      </discourse-assets>
      <p id="native-boot-progress" role="status" style="margin:3rem auto;padding:1rem;max-width:40rem;font:16px system-ui;color:#333">Loading Discourse…</p>
      <section id="main"></section>
      <script type="module" id="native-bounded-boot">
      const boot = JSON.parse(document.getElementById("native-boot-assets").textContent);
      async function preload(url) {
        await new Promise((resolve, reject) => {
          const link = document.createElement("link");
          link.rel = "modulepreload";
          link.href = url;
          link.crossOrigin = "anonymous";
          const timer = setTimeout(() => finish(new Error("Timed out loading " + url)), 20000);
          function finish(error) {
            clearTimeout(timer);
            link.onload = link.onerror = null;
            if (error) { link.remove(); reject(error); } else { resolve(); }
          }
          link.onload = () => finish();
          link.onerror = () => finish(new Error("Failed to load " + url));
          document.head.appendChild(link);
        });
      }
      try {
        // Modulepreload populates the browser module map without evaluating the
        // application. Postorder prevents recursive dependency fetch bursts.
        for (const url of boot.modules) { await preload(url); }
        for (const plugin of boot.plugins) {
          for (const url of plugin.modules) { await preload(url); }
          // The unchanged upstream loader discovers these modulepreload links,
          // imports compatModules and runs plugin-style initialize(container).
          const link = Array.from(document.querySelectorAll('link[rel="modulepreload"]')).find(node => node.href === new URL(plugin.entry, location.href).href);
          if (!link) { throw new Error("Missing paced plugin entry: " + plugin.entry); }
          link.dataset.pluginName = plugin.name;
        }
        await import(boot.locale);
        await import(boot.entry);
        document.getElementById("native-boot-progress")?.remove();
        document.documentElement.dataset.nativeBoot = "complete";
      } catch (error) {
        console.error("Native Discourse boot failed", error);
        document.getElementById("native-boot-progress")?.remove();
        document.documentElement.dataset.nativeBoot = "failed";
        const notice = document.createElement("section");
        notice.id = "native-boot-error";
        notice.style.cssText = "margin:3rem auto;padding:1.5rem;max-width:40rem;font:16px system-ui;color:#222;background:#fff;border:1px solid #ddd";
        const title = document.createElement("h1");
        title.textContent = "Discourse could not finish loading";
        const message = document.createElement("p");
        message.textContent = "A required application asset did not load. Reload to retry.";
        const retry = document.createElement("button");
        retry.type = "button";
        retry.textContent = "Reload page";
        retry.onclick = () => location.reload();
        notice.append(title, message, retry);
        document.body.prepend(notice);
      }
      </script>
      <script defer src="#{attr(update_url)}"></script>
      </body>
      </html>
    HTML
  end

  def render_service_worker(origin)
    descriptor = JSON.parse(File.read(@manifest_path))
    worker_path = File.join(File.dirname(@manifest_path), "service-worker.js")
    source = File.read(worker_path)
    base_url = "#{normalize_origin(origin)}#{@base_uri}"
    worker = source.gsub("__MINIMAL_BASE_URL__", base_url).gsub("__MINIMAL_BASE_PATH__", @base_uri)
    expected = descriptor.fetch("service_worker").fetch("path_placeholders")
    if expected.any? { |placeholder| worker.include?(placeholder) }
      raise "service worker placeholders were not fully expanded"
    end
    worker
  end

  private

  def normalize_topic(topic, preloads)
    raise ArgumentError, "topic must be a Hash" unless topic.is_a?(Hash)
    fields = topic.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
    id = fields.fetch("id")
    id = Integer(id, 10) if id.is_a?(String)
    raise ArgumentError, "topic id must be a positive integer" unless id.is_a?(Integer) && id.positive?
    slug = fields.fetch("slug")
    title = fields.fetch("title")
    unless slug.is_a?(String) && !slug.empty? && !slug.match?(%r{[/?#]})
      raise ArgumentError, "topic slug must be a non-empty path segment"
    end
    raise ArgumentError, "topic title must be a String" unless title.is_a?(String)
    unless preloads.key?("topic_#{id}") || preloads.key?(:"topic_#{id}")
      raise ArgumentError, "topic preload topic_#{id} is required"
    end
    { "id" => id, "slug" => slug, "title" => title }
  rescue KeyError => error
    raise ArgumentError, "topic requires #{error.key.inspect}"
  end

  def normalize_base_uri(value)
    raise ArgumentError, "base_uri must be a String" unless value.is_a?(String)
    return "" if value.empty?
    unless value.start_with?("/") && !value.start_with?("//") && !value.end_with?("/") &&
           value.split("/").drop(1).all? { |part| part.match?(/\A[A-Za-z0-9._~-]+\z/) && part != "." && part != ".." }
      raise ArgumentError, "base_uri must be a normalized path prefix without query/hash/traversal"
    end
    value
  end

  def normalize_origin(value)
    raise ArgumentError, "origin must be a String" unless value.is_a?(String)
    uri = URI.parse(value)
    unless %w[http https].include?(uri.scheme) && uri.host && uri.path.to_s.empty? && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
      raise ArgumentError, "origin must contain only an http(s) scheme and authority"
    end
    uri.to_s.sub(%r{/$}, "")
  rescue URI::InvalidURIError
    raise ArgumentError, "invalid origin"
  end

  def prefixed(path)
    "#{@base_uri}#{path}"
  end

  def core_asset(filename)
    # Rolldown manifest files are relative to the core frontend dist root.
    prefixed("/assets/discourse/#{filename.delete_prefix("/")}")
  end

  def dependency_files(filename, chunks, visited = {})
    return [] if visited[filename]
    visited[filename] = true
    chunk = chunks[filename]
    return [filename] unless chunk
    [*Array(chunk["imports"]).flat_map { |path| dependency_files(path, chunks, visited) }, filename]
  end

  def safe_script_json(value)
    JSON.generate(value).gsub(/[<>&]/) { |char| { "<" => "\\u003c", ">" => "\\u003e", "&" => "\\u0026" }.fetch(char) }
  end

  def attribute_value(value)
    case value
    when true then "true"
    when false then "false"
    when Hash, Array then JSON.generate(value)
    else value.to_s
    end
  end

  def attr(value)
    CGI.escapeHTML(value.to_s)
  end
end
