# An ensure inside a method whose return kind is an OBJECT (a user class),
# inlined into a caller that itself returns an object: the deferred-return
# slot must exist for the kind, so the ensure's exit is `return _retvN;` and
# not a bare `return;` from a non-void C function (which does not build).
# c_type_name names only the builtin kinds; object kinds are declared by
# emit_ctype through their class, and the slot guard has to ask both.
class Ctx
  def initialize
    @n = 0
    @ops = []
  end

  def save = (@n += 1)
  def restore = (@n -= 1)
  def rotate(a) = @ops << a
  def ops = @ops

  def with_state
    save
    begin
      yield self
    ensure
      restore
    end
    self
  end
end

class Node
  attr_reader :tag, :text
  def initialize(tag, text)
    @tag = tag
    @text = text
  end
end

def el(tag, text) = Node.new(tag, text)

def view(ticks)
  el("col", (ctx = Ctx.new
             ctx.rotate(1)
             ctx.with_state do |c|
               c.rotate(ticks * 2)
             end
             ctx.rotate(3)
             ctx.ops.join(",")))
end

3.times { |i| puts view(i).text }
puts view(7).text

# The same shape returning a HEAP object (a class with a subclass never gets
# the by-value layout): the slot is a pointer and defaults to NULL.
class Card
  attr_reader :text
  def initialize(text)
    @text = text
  end
end

class Note < Card
end

def card(ticks)
  Card.new((ctx = Ctx.new
            ctx.with_state do |c|
              c.rotate(ticks + 100)
            end
            ctx.ops.join(",")))
end

2.times { |i| puts card(i).text }
puts Note.new("note").text
