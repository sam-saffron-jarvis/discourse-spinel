# frozen_string_literal: true

module UserStatusMixin


  def include_status?; raise ArgumentError, "unsupported status serialization profile" if @options[:include_status]; @options[:include_status]; end

  def status; raise ArgumentError, "unsupported status serialization profile"; end

  public

end
