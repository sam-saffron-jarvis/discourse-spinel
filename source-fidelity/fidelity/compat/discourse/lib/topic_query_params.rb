# frozen_string_literal: true

module TopicQueryParams
  def build_topic_list_options
    options = {}
    params[:tags] = [params[:tag_name], *Array(params[:tags])].uniq if params[:tag_name].present?

    TopicQuery.public_valid_options.each do |key|
      if params.key?(key.to_s) && (val = params[key.to_s]).present?
        options[key] = val
        raise Discourse::InvalidParameters.new key if !TopicQuery.validate?(key, val)
      end
    end

    # hacky columns get special handling
    options[:topic_ids] = param_to_integer_list(:topic_ids)

    options
  end
end
