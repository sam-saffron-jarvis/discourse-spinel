# frozen_string_literal: true

module JsonError
  def create_errors_json(obj, opts = nil)
    opts ||= {}

    errors = create_errors_array obj
    errors[:error_type] = opts[:type] if opts[:type]
    errors[:extras] = opts[:extras] if opts[:extras]
    errors[:html_message] = true if opts[:html_message]
    errors
  end

  private

  def create_errors_array(obj)
 return { errors: [obj] } if obj.is_a?(String)
 raise ArgumentError, "unsupported non-String JSON error profile"
end

  def self.generic_error
    { errors: [I18n.t("js.generic_error")] }
  end
end
