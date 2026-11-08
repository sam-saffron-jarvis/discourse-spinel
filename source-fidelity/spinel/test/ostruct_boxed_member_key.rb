# A statically known OpenStruct with a boxed key (composition, not a subclass).
require "ostruct"
class MemberBag
  def initialize
    @data = OpenStruct.new(count: 3)
  end
  #: (untyped) -> untyped
  def read(key)
    @data[key]
  end
  #: (untyped, untyped) -> untyped
  def write(key, value)
    @data[key] = value
  end
end
bag = MemberBag.new
p bag.read(:count)
p bag.read("count")
p bag.read(:missing)
p bag.write(:count, 5)
p bag.read("count")
p bag.write("count", false)
p bag.read(:count)
[:read, :write].each do |operation|
  begin
    if operation == :read
      bag.read(7)
    else
      bag.write(7, "bad")
    end
  rescue NoMethodError => error
    puts error.class
  end
end
