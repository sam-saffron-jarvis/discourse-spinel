# A block that always leaves -- `raise` or `throw` -- produces no value, but
# the slot the yield feeds is typed from the OTHER call sites' blocks. The
# splice put a void C expression there, and the program did not build at all:
# `@v = yield`, `t += yield i`, and a bare `yield` in a method carrying a
# rescue each stopped a program CRuby runs. A `return` tail already filled
# the hole; these fill it the same way.

class C
  def set; @v = yield; self; end
  def v; @v; end
end
p C.new.set { 5 }.v
begin; C.new.set { raise "ivar" }; rescue => e; p e.message; end

def acc
  t = 0
  3.times { |i| t += yield i }
  t
end
p acc { |i| i }
begin; p acc { |i| raise "accum" }; rescue => e; p e.message; end

def deflt
  yield
rescue
  -1
end
p deflt { 9 }
p deflt { raise "rescued" }

# the slot's type is whatever the other sites give it
def as_s; s = yield; s + "!"; end
p as_s { "hi" }
begin; as_s { raise "str" }; rescue => e; p e.message; end

def as_f; f = yield; f * 2.0; end
p as_f { 1.5 }
begin; as_f { raise "flt" }; rescue => e; p e.message; end

def as_a; a = yield; a.size; end
p as_a { [1, 2, 3] }
begin; as_a { raise "arr" }; rescue => e; p e.message; end

# a raising site FIRST, before any site that gives the slot its type
def first_raises; x = yield; x + 1; end
begin; first_raises { raise "first" }; rescue => e; p e.message; end
p first_raises { 100 }

# two raising sites against one that answers
def two_raise; x = yield; x + 1; end
p two_raise { 10 }
begin; two_raise { raise "p" }; rescue => e; p e.message; end
begin; two_raise { raise "q" }; rescue => e; p e.message; end

# throw leaves the same way raise does
def thrower; v = yield; v * 2; end
p(catch(:tag) do
  p thrower { 4 }
  thrower { throw :tag, "thrown" }
end)

# an exception class rather than a message
def classy; a = yield; a.to_s; end
p classy { 3 }
begin; classy { raise TypeError, "t" }; rescue => e; p e.class; end
