# frozen_string_literal: true
# Private scoped view context. Only ordinary String/Integer expressions occur
# before the first cache capability. It never returns a body/page.
require "erb"
require "digest"
require_relative "list_body_prefix"
require_relative "source_renderer_sequence"
class ListTemplatePrefixContext
  include PortableListBodyPrefix
  attr_reader :events, :controller
  def initialize(controller)
    @controller = controller
    @list = controller.html_stage_list
    @category = controller.instance_variable_get(:@category)
    @tag_name = controller.instance_variable_get(:@tag_name)
    raise ArgumentError, "unsupported categorized/tagged template context" unless @category.nil? && @tag_name.nil?
    @body_output = +""
    @output_buffer = self
    @events = []
    @category_attempt = nil
    @fault = ENV.fetch("FIDELITY_TEMPLATE_FAULT", "")
  end
  def request; controller.request; end
  def current_user; controller.current_user; end
  def crawler_layout?; controller.use_crawler_layout?; end
  def mobile_device?; MobileDetection.mobile_device?(request.user_agent); end
  def modern_mobile_device?
    raise ArgumentError, "unsupported mobile template profile"
  end
  def params; request.params; end
  def t(key)
    I18n.translate_runtime(key, {}, "list.list", true, false)
  end
  def safe_append=(value)
    @body_output << value
    nil
  end
  def append=(value)
    return nil if value.nil?
    unless value.is_a?(String) || value.is_a?(Integer)
      raise TypeError, "unsupported prefix expression type/trust profile"
    end
    return nil if @fault == "drop-title" && value == @list.topics.first.title
    @body_output << (@fault == "unescaped" ? value.to_s : ERB::Util.html_escape(value.to_s))
    nil
  end
  def category_url_capability(category)
    @category_attempt = category.id
    @events << "category_url_capability_refusal"
    raise HtmlRenderingBoundary, "Category#url requires guarded DistributedCache/Scheduler/MessageBus capability; no subscription/enqueue/publication attempted"
  end
  def view_flow
    @events << "view_flow_receiver"
    self
  end
  def set(name, value)
    raise "view flow set reached before body refusal"
  end
  def _layout_for(*names)
    raise "template yield reached outside declared prefix"
  end
  def prefix_snapshot; @body_output.dup; end
  def body_enter
    @events << "body_template"
  end
  def observation
    prefix = prefix_snapshot
    raise "template literal/table order changed" unless prefix.include?('<table class=\'topic-list\'>') && prefix.include?("<a href='")
    title = @list.topics.first.title
    raise "genuine template title missing/escaping changed" unless prefix.include?(ERB::Util.html_escape(title))
    raise "template request order changed" unless @events == ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template", "category_url_capability_refusal"]
    raise "template boundary did not use genuine category" unless @category_attempt == @list.topics.first.category.id
    {prefix: prefix, sha256: Digest::SHA256.hexdigest(prefix), bytes: prefix.bytesize,
      events: @events, topic_id: @list.topics.first.id, category_id: @category_attempt,
      completed_body: false, layout_executed: false, capability_dispatched: false}
  end
end
class ListTemplateFile
  attr_reader :identifier, :virtual_path
  def initialize(path, kind)
    @identifier = path
    @virtual_path = kind == "body" ? "list/list" : "layouts/application"
    @kind = kind
  end
  def render(view, locals)
    raise "layout executed before body refusal" unless @kind == "body"
    view.body_enter
    view.render_list_body
  end
end
class ListTemplatePrefixRenderer
  include SourceRendererSequence
  def initialize(view, body_path, layout_path, body_sha, layout_sha)
    @view = view
    @body_path, @layout_path, @body_sha, @layout_sha = body_path, layout_path, body_sha, layout_sha
  end
  def checked_file(path, expected, kind)
    raise ArgumentError, "original template disappeared" unless File.file?(path)
    raise ArgumentError, "original template bytes changed" unless Digest::SHA256.hexdigest(File.binread(path)) == expected
    ListTemplateFile.new(path, kind)
  end
  def find_layout(path, keys, formats)
    raise ArgumentError, "unsupported template layout profile" unless path == "application" && keys.empty? && formats == [:html]
    @view.events << "layout_lookup"
    checked_file(@layout_path, @layout_sha, "layout")
  end
  def formats; [:html]; end
  def build_rendered_template(body, template)
    raise "template unexpectedly returned a response"
  end
  def run
    @view.events << "template_lookup"
    template = checked_file(@body_path, @body_sha, "body")
    layout = @view.controller.set_layout
    if ENV.fetch("FIDELITY_TEMPLATE_FAULT", "") == "layout-first"
      find_layout(layout, [], [:html]).render(@view, {})
    end
    render_template(@view, template, layout, {})
  end
end
class HtmlStageObservedController
  def respond_with_list(list)
    @html_events << "responder"
    begin
      super
    rescue HtmlRenderingBoundary => error
      raise unless error.message.start_with?("unimplemented original list/list")
      @template_prefix_context = template_context
      unit = ListTemplatePrefixContext.new(self)
      unit.append = "<unit-only&>"
      raise "template accumulator failed escaping unit control" unless unit.prefix_snapshot == "&lt;unit-only&amp;&gt;"
      renderer = ListTemplatePrefixRenderer.new(@template_prefix_context,
        TemplatePrefixSource::BODY_PATH, TemplatePrefixSource::LAYOUT_PATH,
        TemplatePrefixSource::BODY_SHA, TemplatePrefixSource::LAYOUT_SHA)
      renderer.run
      raise "template continuation unexpectedly returned"
    end
  end
  def template_context; ListTemplatePrefixContext.new(self); end
end
