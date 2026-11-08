# frozen_string_literal: true
# Admission ONLY to the bounded fail-closed request/controller experiment.
# Not an HTML response profile, not public transport, never JSON admission.
class PortableHtmlStageIngress
  def self.validate!(env)
    unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/latest" && env["HTTP_ACCEPT"] == "text/html"
      raise ArgumentError, "unsupported HTML stage method/path/accept"
    end
    PortableJsonIngress.validate_direct_context!(env)
    true
  end
end
