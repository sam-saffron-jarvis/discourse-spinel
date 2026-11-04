# A member name a second class also declares makes the read a poly dispatch,
# whose value is an sp_RbVal, while the synthesized constructor's parameter is
# the member's own C type. The constructor call has to coerce, exactly as it
# already boxes for the opposite case (#4348).
class Unbuilt
  def message = nil
  def code = nil
end

class Finding < Data.define(:message)
  def self.refused(refusal)
    new(message: refusal.message)          # receiverless, inside a class method
  end

  def self.qualified(refusal)
    Finding.new(message: refusal.message)  # through the receiver
  end
end

Pair = Struct.new(:code)
class Pair
  def self.of(other)
    new(other.code)                        # positional, non-string member
  end
end

[Finding.new(message: "out of shape")].each do |one|
  puts Finding.refused(one).message
  puts Finding.qualified(one).message
end

[Pair.new(7)].each { |one| p Pair.of(one).code }
