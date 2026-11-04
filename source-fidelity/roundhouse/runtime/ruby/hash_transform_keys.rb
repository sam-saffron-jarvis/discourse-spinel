# frozen_string_literal: true
module ActiveSupport
  # Rails' destructive recursive key walk, including snapshot/delete/store
  # collision order. Mutate nested containers themselves: aliases observe it.
  def self.deep_symbolize_keys!(hash)
    hash.keys.each do |key|
      item = hash.delete(key)
      converted = if key.is_a?(String)
        key.to_sym
      elsif key.is_a?(Symbol) || key.is_a?(Integer) || key.is_a?(Float) || key.nil? || key == true || key == false
        key
      else
        raise NotImplementedError.new("deep_symbolize_keys! custom key conversion is not supported")
      end
      hash[converted] = ActiveSupport.deep_symbolize_value!(item)
    end
    hash
  end

  def self.deep_symbolize_value!(value)
    if value.is_a?(Hash)
      ActiveSupport.deep_symbolize_keys!(value)
    elsif value.is_a?(Array)
      value.map! { |item| ActiveSupport.deep_symbolize_value!(item) }
    end
    value
  end
end
