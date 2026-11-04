# `k.new(x)` where k is a Class held as a VALUE -- a parameter, or anything
# else the compiler cannot fold to one class.
#
# The dispatch is a switch over the class token with one arm per class whose
# constructor could take these arguments, and the arm test demanded
# argc == nparams == nrequired. A constructor as ordinary as
# `initialize(path, initheader = nil)` therefore matched NO class, the switch
# came out empty, and the call answered the nil seed with no diagnostic
# (#4417). Nothing crashed until the nil was used.
#
# The report read the trigger as nesting, because the class that bit was
# `Net::HTTP::Get`. It is not nesting: `Plain` below is top-level and does it
# too. What decides it is whether `initialize` has an optional parameter.
#
# The other half is the empty switch itself. A class the dispatch has no arm
# for is a program that cannot construct it, and that is a raise -- the
# sibling emitter for a poly receiver has always said so. The last two lines
# check that a class whose constructor cannot take the given count raises
# rather than answering nil; CRuby raises ArgumentError and spinel raises
# NoMethodError, so the arm is checked by the fact of the raise.
class Base
  def initialize(m, p, h = nil)
    @m = m
    @p = p
    @h = h
  end

  def tag
    "#{@m}/#{@p}/#{@h.inspect}"
  end
end

class Plain
  def initialize(p, h = nil)
    @p = p
    @h = h
  end

  def tag
    "plain/#{@p}/#{@h.inspect}"
  end
end

class Sub < Base
  def initialize(p, h = nil)
    super("SUB", p, h)
  end
end

module M
  class Nested < Base
    def initialize(p, h = nil)
      super("NEST", p, h)
    end
  end
end

class AllOptional
  def initialize(a = "d1", b = "d2")
    @a = a
    @b = b
  end

  def tag
    "opt/#{@a}/#{@b}"
  end
end

class Exact
  def initialize(a, b)
    @a = a
    @b = b
  end

  def tag
    "exact/#{@a}/#{@b}"
  end
end

class NoArgs
  def initialize
    @z = 0
  end

  def tag
    "noargs"
  end
end

def mk1(k, u)
  k.new(u)
end

def mk2(k, a, b)
  k.new(a, b)
end

# one argument against a constructor whose second is optional
p mk1(Plain, "x").tag
p mk1(Sub, "x").tag
p mk1(M::Nested, "x").tag
p mk1(AllOptional, "x").tag

# both arguments given, so the optional one is not defaulted
p mk2(Plain, "x", "h").tag
p mk2(Sub, "x", "h").tag
p mk2(AllOptional, "x", "y").tag

# a constructor with no optional parameters at all still works
p mk2(Exact, "x", "y").tag

# nil is not an answer: a class that cannot take one argument raises
begin
  mk1(NoArgs, "x")
  puts "NOT REACHED"
rescue StandardError
  puts "raised"
end

# NOT tested here, because CRuby and spinel disagree and this file is diffed
# against CRuby: a parameter typed by its DEFAULT. `initialize(a = 1)` types
# `a` Integer, a statically known `Klass.new("x")` widens it because that call
# site is visible to the inference, and a class-VALUE call site is not -- so
# the class has no arm for a String and the dispatch raises where CRuby
# constructs. That is in docs/limitations.md. What matters here is that it
# RAISES: before this change the arm was selected anyway and the string's
# address was read as an Integer.
