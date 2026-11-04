# A method returning a BY-VALUE object class, with an ensure or a rescue in its
# body. emit_ctype declares such a class as a bare struct, and default_value
# cannot know that -- it takes a TyKind, and the value-ness lives on the class
# -- so the begin's result slot was initialised to NULL and did not build
# (#4270). #4268 made the same distinction for the ensure's own deferred-return
# slot; this is that question one slot over.
class Box
  attr_reader :v
  def initialize(v)
    @v = v
  end
end

# a heap class through the same shapes, which #4268 fixed and must stay fixed
class Heap
  attr_reader :a, :b
  def initialize(a, b)
    @a = a
    @b = b
  end
end

def val_ensure(v)
  begin
    Box.new(v)
  ensure
    $ensured = true
  end
end

def val_rescue(v)
  begin
    raise "negative" if v < 0
    Box.new(v)
  rescue
    Box.new(0)
  end
end

def val_ensure_and_rescue(v)
  begin
    raise "negative" if v < 0
    Box.new(v)
  rescue
    Box.new(-1)
  ensure
    $both = true
  end
end

def heap_ensure(v)
  begin
    Heap.new(v, v * 2)
  ensure
    $heap_ensured = true
  end
end

def val_plain(v)
  Box.new(v)
end

p val_ensure(3).v
p val_rescue(5).v
p val_rescue(-1).v
p val_ensure_and_rescue(4).v
p val_ensure_and_rescue(-2).v
p heap_ensure(7).a
p heap_ensure(7).b
p val_plain(9).v
p [$ensured, $both, $heap_ensured]
