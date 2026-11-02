# frozen_string_literal: true
# Read-only Rails oracle for discourse-details cooking. No source-tree writes,
# site-setting mutations, post saves, or email/editor hooks.
require "json"
require "nokogiri"
require "yaml"
require "digest"

EXPECTED_DATABASE_URL = "postgres://discourse@127.0.0.1:5499/discourse_development"
abort "task PG identity mismatch" unless ENV["DATABASE_URL"] == EXPECTED_DATABASE_URL
abort "task Valkey identity mismatch" unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"
abort "PG must be configured read-only" unless ENV.fetch("PGOPTIONS", "").include?("default_transaction_read_only=on")

root = File.expand_path("..", __dir__)
plugin_settings = YAML.safe_load_file(File.join(root, "../discourse/plugins/discourse-details/config/settings.yml"))
setting_default = plugin_settings.fetch("plugins").fetch("details_enabled").fetch("default")

# All inputs are deliberately synthetic post bodies; outputs are always obtained
# from the pinned Rails PrettyText.cook implementation.
cases = [
  ["closed", "[details=Closed summary]\nClosed paragraph body.\n[/details]"],
  ["open", "[details=\"Open summary\" open]\nOpen paragraph body.\n[/details]"],
  ["nested", "[details=Outer summary]\nOuter paragraph body.\n[details=Inner summary]\nInner paragraph body.\n[/details]\n[/details]"],
  ["summary_escaping", "[details=\"<script>alert('summary')</script>\"]\nEscaping paragraph body.\n[/details]"],
  ["sanitizer_elided", "<details class='elided' open onclick='alert(1)'><summary title='safe title' onclick='alert(2)'>Elided summary</summary><p>Elided paragraph body.</p><script>alert('raw')</script></details>"],
  ["title_open_unsupported_attrs", "[details open title=\"Unsupported title\" class=\"details__boxed\"]\nUnsupported attrs paragraph body.\n[/details]"],
  ["reader_combined", <<~BODY.chomp],
    [details=Closed summary]
    Closed paragraph body.
    [/details]

    [details="Open summary" open]
    Open paragraph body.
    [/details]

    [details=Outer summary]
    Outer paragraph body.
    [details=Inner summary]
    Inner paragraph body.
    [/details]
    [/details]

    [details="<script>alert('escaped summary')</script>"]
    Escaped summary paragraph body.
    [/details]

    <details class='elided' onclick='alert(1)'><summary>Sanitizer summary</summary><p>Sanitizer paragraph body.</p><script>alert('raw')</script></details>

    [details open title="Unsupported title" class="details__boxed"]
    Unsupported attrs paragraph body.
    [/details]
  BODY
]

module DetailsFixtureSettingOverride
  def details_enabled
    override = Thread.current[:details_fixture_setting]
    return override unless override.nil?
    super
  end

  def get(name, scoped_to = nil)
    override = Thread.current[:details_fixture_setting]
    return override if name.to_s == "details_enabled" && !override.nil?
    super
  end
end
SiteSetting.singleton_class.prepend(DetailsFixtureSettingOverride)

connection = ActiveRecord::Base.connection
artifact = { "read_only" => true, "source" => "actual PrettyText.cook", "source_setting" => { "default" => setting_default } }
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  ActiveRecord::Base.uncached do
    identity = connection.select_one("SELECT current_database(), current_user, inet_server_addr()::text, inet_server_port(), current_setting('default_transaction_read_only')")
    raise "source task PG identity/read-only mismatch: #{identity.inspect}" unless identity["current_database"] == "discourse_development" && identity["current_user"] == "discourse" && identity["inet_server_addr"].to_s.split("/").first == "127.0.0.1" && identity["inet_server_port"].to_i == 5499 && identity["current_setting"] == "on"
    artifact["task_pg_identity"] = identity
    artifact["source_setting"]["live"] = SiteSetting.details_enabled
    artifact["source_setting"]["client"] = JSON.parse(SiteSetting.client_settings_json).fetch("details_enabled")
    raise "source client setting differs from actual getter" unless artifact["source_setting"]["client"] == artifact["source_setting"]["live"]
    counts = connection.select_one(<<~SQL)
      SELECT count(*)::integer AS posts,
    count(*) FILTER (WHERE cooked ILIKE '%<details%')::integer AS details_posts,
    count(*) FILTER (WHERE cooked ILIKE '%<details%')::integer AS cooked_posts_with_details,
        COALESCE(sum((length(lower(cooked)) - length(replace(lower(cooked), '<details', ''))) / length('<details')), 0)::integer AS cooked_details_open_tags,
        COALESCE(sum((length(lower(cooked)) - length(replace(lower(cooked), '<summary', ''))) / length('<summary')), 0)::integer AS cooked_summaries
      FROM posts WHERE deleted_at IS NULL
    SQL
    artifact["live_inventory"] = counts.transform_values(&:to_i).merge("read_only" => true)
    # Actual source stored-content getter on real anonymous-visible posts. Hashes
    # support native HTTP comparisons without copying live post response bodies.
    guardian = Guardian.new
    public_ids = connection.select_values(<<~SQL)
      SELECT p.id FROM posts p JOIN topics t ON t.id=p.topic_id JOIN categories c ON c.id=t.category_id
      WHERE p.deleted_at IS NULL AND t.deleted_at IS NULL AND t.archetype <> 'private_message'
        AND c.read_restricted IS NOT TRUE AND p.post_type IN (1,2,3) AND p.hidden IS NOT TRUE
        AND NOT EXISTS (SELECT 1 FROM shared_drafts d WHERE d.topic_id=t.id)
      ORDER BY p.id LIMIT 200
    SQL
    artifact["live_inventory"]["visible_source_cooked"] = Post.where(id: public_ids).order(:id).filter_map do |post|
      next unless guardian.can_see?(post)
      cooked = BasicPostSerializer.new(post, root: false, scope: guardian).cooked
      { "post_id" => post.id, "topic_id" => post.topic_id, "sha256" => Digest::SHA256.hexdigest(cooked) }
    end

    artifact["cases"] = cases.map do |name, input|
      Thread.current[:details_fixture_setting] = true
      cooked = PrettyText.cook(input)
      fragment = Nokogiri::HTML.fragment(cooked)
      tree = fragment.css("details").map do |node|
        { "summary" => node.element_children.find { |child| child.name == "summary" }&.text,
          "open" => node.key?("open"),
          "child_details" => node.css("details").length,
          "children" => node.element_children.map(&:name) }
      end
      { "name" => name, "input" => input, "cooked" => cooked, "tree" => tree }
    end
    by_name = artifact.fetch("cases").index_by { |entry| entry.fetch("name") }
    raise "closed details summary/body source assertion" unless by_name["closed"]["tree"][0]["summary"].include?("Closed summary") && !by_name["closed"]["tree"][0]["open"] && by_name["closed"]["cooked"].include?("Closed paragraph body.")
    raise "open details summary/body source assertion" unless by_name["open"]["tree"][0]["summary"].include?("Open summary") && by_name["open"]["tree"][0]["open"] && by_name["open"]["cooked"].include?("Open paragraph body.")
    raise "nested details tree source assertion" unless by_name["nested"]["tree"].length == 2 && by_name["nested"]["tree"].map { |node| node["summary"] }.any? { |value| value.include?("Outer summary") } && by_name["nested"]["tree"].map { |node| node["summary"] }.any? { |value| value.include?("Inner summary") }
    raise "summary escaping source assertion" if by_name["summary_escaping"]["cooked"].include?("<script") || !by_name["summary_escaping"]["cooked"].include?("&lt;script&gt;")
    sanitizer = by_name["sanitizer_elided"]["cooked"]
    raise "raw HTML sanitizer source assertion" if sanitizer.include?("onclick") || sanitizer.include?("<script") || !sanitizer.include?("details class=\"elided\"") || !sanitizer.include?("open=\"\"") || !sanitizer.include?("title=\"safe title\"")
    unsupported = by_name["title_open_unsupported_attrs"]["cooked"]
    raise "unsupported details attributes source assertion" if unsupported.include?("Unsupported title") || unsupported.include?("details__boxed")
    combined = by_name.fetch("reader_combined").fetch("cooked")
    %w[Closed\ summary Open\ summary Outer\ summary Inner\ summary].each do |label|
      raise "combined browser label missing: #{label}" unless combined.include?(label)
    end

    # Changing enablement is stylesheet selection, never suppression of already
    # stored cooked. Invoke the actual source getter on unsaved test-only Posts.
    artifact["stored_serializer_by_setting"] = {}
    [true, false].each do |enabled|
      Thread.current[:details_fixture_setting] = enabled
      values = artifact.fetch("cases").map do |item|
        post = Post.new(cooked: item.fetch("cooked"), hidden: false)
        actual = BasicPostSerializer.new(post, root: false, scope: guardian).cooked
        raise "source stored cooked rewritten for #{item.fetch('name')} setting=#{enabled}" unless actual == item.fetch("cooked")
        { "name" => item.fetch("name"), "cooked" => actual }
      end
      artifact["stored_serializer_by_setting"][enabled ? "enabled" : "disabled"] = values
    end

    # Test-local accessor overrides only; no DB/SiteSetting writes. Measure the
    # actual source outcome for IDENTICAL input, without assuming cooker gating.
    settings_input = "[details=Setting semantic summary]\nSetting semantic body.\n[/details]"
    Thread.current[:details_fixture_setting] = true
    enabled_cooked = PrettyText.cook(settings_input)
    enabled_css_assets = Discourse.find_plugin_css_assets(only: ["discourse-details"], mobile_view: true, desktop_view: true, request: nil)
    Thread.current[:details_fixture_setting] = false
    disabled_cooked = PrettyText.cook(settings_input)
    disabled_css_assets = Discourse.find_plugin_css_assets(only: ["discourse-details"], mobile_view: true, desktop_view: true, request: nil)
    artifact["setting_semantics"] = {
      "enabled" => { "setting" => true, "cooked" => enabled_cooked, "details_elements" => Nokogiri::HTML.fragment(enabled_cooked).css("details").length,
        "plugin_css_assets" => enabled_css_assets },
      "disabled" => { "setting" => false, "cooked" => disabled_cooked, "details_elements" => Nokogiri::HTML.fragment(disabled_cooked).css("details").length,
        "plugin_css_assets" => disabled_css_assets }
    }
    raise "source enabled CSS missing" unless enabled_css_assets == ["discourse-details"]
    raise "source disabled CSS present" unless disabled_css_assets.empty?
    raise "source cooker setting observation changed" unless enabled_cooked == disabled_cooked
    artifact["setting_semantics"]["cook_output_equal"] = enabled_cooked == disabled_cooked
    artifact["setting_semantics"]["cook_uses_setting"] = enabled_cooked != disabled_cooked
    artifact["setting_semantics"]["css_tracks_setting"] = artifact.dig("setting_semantics", "enabled", "plugin_css_assets") != artifact.dig("setting_semantics", "disabled", "plugin_css_assets")
    artifact["setting_semantics"]["meaning"] = "with identical input, details_enabled leaves PrettyText.cook output unchanged but filters discourse-details CSS assets"
  ensure
    Thread.current[:details_fixture_setting] = nil
  end
  raise ActiveRecord::Rollback
end

out = File.join(root, "build/details/source-fixtures.json")
File.write(out, JSON.generate(artifact))
puts "PASS actual PrettyText.cook details fixtures and read-only live inventory (#{artifact.fetch('cases').length} cases)"
