# frozen_string_literal: true
# Fixed original :latest action and actual JSON responder. Not a data backend.
module PortableLatestJsonAction
  def latest(options = nil)
    return super unless request.format.json?
    latest_json(options)
  end

  def latest_json(options = nil)
    raise ArgumentError, "unsupported non-JSON latest profile" unless request.format.json?
    filter = :latest
    list_opts = build_topic_list_options
      list_opts.merge!(options) if options
      if params[:category].blank? && filter == :latest &&
           !SiteSetting.show_category_definitions_in_topic_lists
        list_opts[:no_definitions] = true
      end

      list = TopicQuery.new(current_user, list_opts).list_latest

      raise ArgumentError, "unsupported shared-draft JSON request profile" if guardian.can_create_shared_draft?

      list.more_topics_url = construct_latest_json_url_with(:next, list_opts)
      list.prev_topics_url = construct_latest_json_url_with(:prev, list_opts)



      respond_with_json_list(list)
  end

  def construct_latest_json_url_with(action, opts, url_prefix = nil)
  raise ArgumentError, "unsupported unicode JSON URL profile" if SiteSetting.unicode_usernames
    method = url_prefix.blank? ? "#{action_name}_path" : "#{url_prefix}_#{action_name}_path"

    page_params =
      case action
      when :prev
        latest_json_prev_page_params
      when :next
        latest_json_next_page_params
      else
        raise "unreachable"
      end

    opts = opts.dup



    opts.delete(:category) if page_params.include?(:category_slug_path_with_id)

    url = latest_path(format: "json", params: opts.merge(page_params).compact.except(:format)).sub(".json?", "?")

    # Unicode usernames need to be encoded when calling Rails' path helper. However, it means that the already
    # encoded username are encoded again which we do not want. As such, we unencode the path once when unicode usernames
    # have been enabled.


    url
  end

  def latest_json_next_page_params
    latest_json_page_params.merge(page: params[:page].to_i + 1)
  end

def latest_json_prev_page_params
    pg = params[:page].to_i
    if pg > 1
      latest_json_page_params.merge(page: pg - 1)
    else
      latest_json_page_params.merge(page: nil)
    end
  end

def latest_json_page_params
 raise ArgumentError, "unsupported categorized latest JSON route" unless controller_path == "list" && action_name == "latest"
    route_params = { format: "json" }



    %i[username group_name groupname period].each do |key|
      route_params[key] = params[key] if params[key].present?
    end

    route_params
  end

  def respond_with_json_list(list)
    discourse_expires_in 1.minute
    # Fixed TopicList serializer expansion of serialize_data/render_json_dump.
    # All attributes and associations still come from the real serializer.
    payload = TopicListSerializer.new(list, scope: guardian).as_json
    render json: JSON.generate(payload.as_json), status: 200
  end
end
