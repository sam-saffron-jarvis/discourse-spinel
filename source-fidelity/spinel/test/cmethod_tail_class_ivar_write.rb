# A class method whose last statement writes a class-level ivar answers the
# written value, as any tail assignment does (#4508). Each value kind reaches
# the return slot: a Hash, an Integer, a String, an Array, an object.
class Point
  attr_reader :x
  def initialize(x); @x = x; end
end
class Config
  @parsed = nil
  @n = 0
  @s = nil
  @a = nil
  @o = nil

  def self.parsed
    return @parsed if @parsed
    @parsed = { "key" => "value" }
  end

  def self.get(key)
    sections = parsed
    sections[key]
  end

  def self.setn
    @n = 5
  end

  def self.sets
    @s = "str"
  end

  def self.seta
    @a = [1, "a"]
  end

  def self.seto
    @o = Point.new(3)
  end
end
p Config.get("key")
p Config.get("key")
p Config.setn
p Config.sets
p Config.seta
p Config.seto.x
