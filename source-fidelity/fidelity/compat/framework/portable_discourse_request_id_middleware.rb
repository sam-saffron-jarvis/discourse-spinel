# frozen_string_literal: true
# Actual Actionpack RequestId presence/sanitization algorithm in the
# Discourse fast_blank context; same env/call boundary as the framework.
class PortableDiscourseRequestIdMiddleware < ActionDispatch::RequestIdMiddleware
  def make_request_id(request_id)
    if PortableResponseMiddlewareDeclarations.blank_header?(request_id)
      SecureRandom.uuid
    else
      request_id.gsub(/[^\w\-@]/, "")[0, 255]
    end
  end
end
