# A native-bound object (StringScanner, a native_struct) reached through a
# poly slot: respond_to? consults its declared bindings, and a call with
# arguments dispatches to them beside the user class sharing the slot (#4504).
require "strscan"

class Fake
  def pos = 7
  def rest_size = 1
  def peek(n) = "fake#{n}"
end

class Holder
  def initialize(s)
    @s = s
  end

  def probe
    if @s.respond_to?(:skip_until)
      m = @s.skip_until(/b/)
    else
      m = [@s.pos, @s.rest_size]
    end
    p m
    p @s.pos
    p @s.peek(2)
    p @s.respond_to?(:peek)
    p @s.respond_to?(:matched)
    if @s.respond_to?(:matched)
      p @s.matched
      p @s.check(/c/)
      r = @s.reset
      p r.pos
    end
  end
end

Holder.new(StringScanner.new("abcd")).probe
Holder.new(Fake.new).probe
