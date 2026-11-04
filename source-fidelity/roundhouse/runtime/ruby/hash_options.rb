# frozen_string_literal: true
module ActiveSupport
  # Rails' exact destructive reverse merge: receiver values (even nil/false)
  # win. Core replace preserves identity and copies the merged hash's defaults.
  def self.reverse_merge!(hash, other_hash)
    hash.replace(other_hash.merge(hash))
  end

  # Rails Hash#assert_valid_keys after the lowerer proves flat key arguments.
  # No coercion: :key and "key" differ. Read the original hash in insertion
  # order, raise on the first invalid key, return the SAME hash on success.
  def self.assert_valid_keys(hash, valid_keys)
    hash.each do |key, _value|
      unless valid_keys.include?(key)
        raise ArgumentError.new("Unknown key: #{key.inspect}. Valid keys are: #{valid_keys.map { |valid| valid.inspect }.join(', ')}")
      end
    end
    hash
  end
end
