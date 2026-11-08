# frozen_string_literal: true
# Addressable::URI.encode_component's default RESERVED_AND_UNRESERVED byte
# contract, expanded to ordinary shared Ruby for the supported String input.
# Original package source and differential controls are recorded separately.
class PortableAvatarEncoding
  SAFE_ASCII = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:/?#[]@!$&'()*+,;=-._~"

  def self.component(value)
    return nil if value.nil?
    raise TypeError, "avatar URI component must be a String" unless value.is_a?(String)
    result = +""
    value.bytes.each do |byte|
      if byte < 128 && SAFE_ASCII.include?(byte.chr)
        result << byte.chr
      else
        result << "%" << byte.to_s(16).upcase.rjust(2, "0")
      end
    end
    result
  end
end
