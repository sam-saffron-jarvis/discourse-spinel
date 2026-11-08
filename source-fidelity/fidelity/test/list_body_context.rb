# frozen_string_literal: true
require_relative "emitted/runtime/action_view/html_fragment"
require_relative "native_list_body"
# Controller stores the parsed query Hash; preserve Rails view's indifferent
# String/Symbol parameter read protocol without changing its real values.
class ListBodyParams
  def initialize(values); @values = values; end
  def [](key); @values[key.to_s]; end
  def key?(key); @values.key?(key.to_s); end
end
module ListBodyViewProtocol
  def acquire_body_assigns(controller)
    @rss = controller.instance_variable_get(:@rss)
    @rss_link = controller.instance_variable_get(:@rss_link)
    @rss_description = controller.instance_variable_get(:@rss_description)
    @params = controller.instance_variable_get(:@params)
    @title = controller.instance_variable_get(:@title)
    @description_meta = controller.instance_variable_get(:@description_meta)
    @head_output = +""
    @title_output = +""
    @incomplete_capture = +""
    @body_returned = false
  end
  def guardian; @controller.guardian; end
  def params; ListBodyParams.new(@controller.params); end
  def t(key, **options)
    I18n.translate_runtime(key.to_s, options, "list.list", true, false)
  end
  def list_translation(key); I18n.translate_runtime(key.to_s, {}, "", false, false); end
  def content_for(slot)
    captured = capture_list_body { yield }
    case slot
    when :head then @head_output << captured.to_s
    when :title then @title_output << captured.to_s
    else raise ArgumentError, "unsupported original list slot"
    end
    nil
  end
  def auto_discovery_link_tag(type, options, title:)
    @events << "rss_helper_boundary"
    raise HtmlRenderingBoundary, "original list body reached RSS helper acquisition; no fabricated link returned"
  end
  def crawlable_meta_data(**options)
    @events << "metadata_helper_boundary"
    raise HtmlRenderingBoundary, "original list body requires genuine metadata image/helper acquisition"
  end
  # Scope is the actual original Time/date_only call, not a general I18n.l API.
  # Uses current real locale/resources; no baked month/format/output values.
  def localize_list_date(value)
    raise TypeError, "list timestamp is not Time" unless value.is_a?(Time)
    format = I18n.translate_runtime("time.formats.date_only", {}, "", false, true)
    format = format.gsub(/%(|\^)[aAbBpP]/) do |token|
      key = case token
      when "%a", "%^a" then "date.abbr_day_names"
      when "%A", "%^A" then "date.day_names"
      when "%b", "%^b" then "date.abbr_month_names"
      when "%B", "%^B" then "date.month_names"
      else ""
      end
      if token.end_with?("p") || token.end_with?("P")
        text = I18n.translate_runtime(value.hour < 12 ? "time.am" : "time.pm", {}, "", false, true)
        token.end_with?("p") ? text.upcase : text.downcase
      else
        index = token.end_with?("a") || token.end_with?("A") ? value.wday : value.mon
        names = JSON.parse(File.read(File.join(Rails.root.to_s, "config/list_date_names.json")))[I18n.locale.to_s][key]
        raise "missing actual localized list date names" unless names.is_a?(Array) && (names.size == 7 || names.size == 13)
        text = names[index]
        raise TypeError, "localized list date name is not String" unless text.is_a?(String)
        token.include?("^") ? text.upcase : text
      end
    end
    value.strftime(format)
  end
  def set(name, value)
    raise "unsupported body view-flow slot" unless name == :layout
    @layout_body = value.to_s.dup
    raise "body return did not preserve accumulated buffer" unless @layout_body == prefix_snapshot
    @body_returned = ENV.fetch("FIDELITY_BODY_FAULT", "") != "missing-body-return"
    @events << "view_flow_set"
    nil
  end
  def layout_boundary
    raise "layout executed before completed body" unless @body_returned
    @events << "layout_render"
    raise HtmlRenderingBoundary, "complete original list body acquired; layout helper continuation not yet installed"
  end
  def expected_body_events
    ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template", "view_flow_set", "layout_render"]
  end
  def body_stage_observation
    text = @body_returned ? @layout_body : prefix_snapshot
    raise "list body omitted materialized rows" unless text.scan('<tr class="topic-list-item">').size == @list.topics.size
    @list.topics.each do |topic|
      raise "list body dropped/changed genuine title" unless text.include?(ERB::Util.html_escape(topic.title))
    end
    raise "body/layout sequence changed" unless @events[0,4] == ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template"] && @body_returned
    raise "body view-flow ordering changed" unless @events == expected_body_events
    raise "list RSS head missing" unless !@rss || @head_output.scan('rel="alternate"').size == 2
    expected_url = ERB::Util.html_escape(Discourse.base_url_no_prefix + request.fullpath)
    raise "list metadata head missing" unless @head_output.include?('property="og:url" content="' + expected_url + '"')
    first = @controller.html_stage_list.topics.first
    category_urls = CategoryCacheBootstrap.lease.category_urls
    {prefix: text, bytes: text.bytesize, sha256: Digest::SHA256.hexdigest(text), events: @events,
      topic_id: first.id, category_id: first.category.id, category_url: category_urls[first.category.id.to_s],
      category_urls: category_urls, head: @head_output, incomplete_capture: @incomplete_capture,
      rendered_rows: @list.topics.size, completed_body: @body_returned, layout_executed: false,
      capability_dispatched: true}
  end
end
class ListBodyContext < ListTemplatePrefixContext
  include ListBodyViewProtocol
  include NativeListBody
  def initialize(controller)
    super
    acquire_body_assigns(controller)
  end
  def append=(value)
    if value.is_a?(ActionView::HtmlFragment)
      @body_output << value.to_s
      nil
    else
      super(value)
    end
  end
  def to_s; @body_output.dup; end
  def raw(value); ActionView::HtmlFragment.new(value.to_s); end
  def h(value); ActionView::HtmlFragment.new(ERB::Util.html_escape(value.to_s)); end
  def trusted_list_html(value)
    raise TypeError, "non-string trusted excerpt" unless value.is_a?(String)
    ActionView::HtmlFragment.new(value)
  end
  def capture_list_body
    previous = @body_output
    @body_output = +""
    begin
      yield
      @body_output.dup
    rescue HtmlRenderingBoundary
      @incomplete_capture = @body_output.dup
      raise
    ensure
      @body_output = previous
    end
  end
  def observation; body_stage_observation; end
end
class HtmlStageObservedController
  def template_context; ListBodyContext.new(self); end
end

class ListTemplateFile
  def render(view, locals)
    return view.layout_boundary unless @kind == "body"
    view.body_enter
    view.render_list_body
  end
end
