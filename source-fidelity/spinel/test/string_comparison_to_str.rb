# A String comparison converts an operand that answers #to_str
# (CRuby's rb_check_string_type at String#<=>, #casecmp, #casecmp? and the
# ordered operators and #between? Comparable builds on <=>). An operand that
# answers no #to_str keeps the comparison's own refusal.

class Wrap
  def initialize(s)
    @s = s
  end

  def to_str
    @s
  end
end

class Sub < Wrap
end

class Plain
end

# A #to_str the analysis types String that answers the nil String: CRuby's
# rb_check_string_type reads a nil answer as "no conversion", so the
# comparison refuses rather than reading it as "".
class Maybe
  def initialize(s = nil)
    @s = s
  end

  def to_str
    @s
  end
end

# A #to_str the analysis can only pin to poly: CRuby checks the ANSWER as well
# as the method, and one that is neither nil nor a String is a TypeError,
# named after both classes.
class Loose
  def initialize(s, bad)
    @s = s
    @bad = bad
  end

  def to_str
    return 42 if @bad
    @s
  end
end

# the same poly shape, answering nil -- which is "no conversion" and not an
# error, so each method gives its own refusal
class Vague
  def initialize(s, none)
    @s = s
    @none = none
  end

  def to_str
    return nil if @none
    @s
  end
end

def report
  yield
rescue => e
  puts e.class
end

# where the message is the point: which class the comparison names, and
# CRuby's own wording for a #to_str that answers the wrong class
def report_msg
  yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

# --- the refusals first, so a GC-stress run reaches them before the churn ---
report { puts("abc" < Plain.new) }
report { puts("abc".between?(Plain.new, Plain.new)) }
report { puts("abc" < 1) }
report_msg { puts("abc" <=> Loose.new("abd", true)) }
report_msg { puts("abc" < Loose.new("abd", true)) }
report_msg { puts("abc".casecmp(Loose.new("ABD", true))) }

# --- <=> converts and compares ---
p("abc" <=> Wrap.new("abc"))
p("abc" <=> Wrap.new("abd"))
p("abc" <=> Wrap.new("abb"))

# --- casecmp / casecmp? convert ---
p("abc".casecmp(Wrap.new("ABC")))
p("abc".casecmp(Wrap.new("ABD")))
p("abc".casecmp?(Wrap.new("ABC")))
p("abc".casecmp?(Wrap.new("ABD")))

# --- the ordered operators, built on <=>, convert too ---
p("abc" < Wrap.new("abd"))
p("abc" <= Wrap.new("abc"))
p("abc" > Wrap.new("abb"))
p("abc" >= Wrap.new("abc"))
p("abc" > Wrap.new("abd"))

# --- between?, with object bounds and with one of each ---
p("abc".between?(Wrap.new("aaa"), Wrap.new("abd")))
p("abc".between?(Wrap.new("aaa"), "abd"))
p("abc".between?("aaa", Wrap.new("abd")))
p("abc".between?(Wrap.new("abd"), Wrap.new("abz")))

# --- #to_str inherited from a superclass ---
p("abc" <=> Sub.new("abc"))
p("abc".casecmp(Sub.new("ABD")))
p("abc" < Sub.new("abd"))

# --- the operand reached through a method return ---
def make(s)
  Wrap.new(s)
end

p("abc" <=> make("abd"))
p("abc" < make("abd"))
p("abc".casecmp(make("ABD")))

# --- a #to_str the analysis pins to poly, answering a String ---
p("abc" <=> Loose.new("abd", false))
p("abc".casecmp(Loose.new("ABD", false)))
p("abc" < Loose.new("abd", false))

# --- a BOXED operand: the element type is not settled ---
mixed = [Wrap.new("abd"), 1]
boxed = mixed[0]
p("abc" <=> boxed)
p("abc".casecmp(boxed))
p("abc".casecmp?(boxed))
p("abc" < boxed)
p("abc" <= boxed)
p("abc" > boxed)
p("abc" >= boxed)

# #between? through the boxed side needs a boxed receiver too: a typed
# receiver with boxed bounds is the shape that does not compile at all
boxed_lo = [Wrap.new("aaa"), 1][0]
boxed_hi = [Wrap.new("abd"), 1][0]
boxed_recv = ["abc", 1][0]
p(boxed_recv.between?(boxed_lo, boxed_hi))

# --- a boxed RECEIVER, converting a typed operand ---
strs = ["abc", 1]
recv = strs[0]
p(recv <=> Wrap.new("abd"))
p(recv.casecmp(Wrap.new("ABD")))

# --- guards: a class answering no #to_str keeps every answer it had, at the
#     seven methods where that answer is the comparison's own. #<=> is not
#     pinned for such a class: it keeps master's NoMethodError, where CRuby
#     answers Object#<=>'s nil (or -(obj <=> self) for a class defining <=>),
#     which is a rule of its own and not this conversion ---
p("abc".casecmp(Plain.new))
p("abc".casecmp?(Plain.new))
report_msg { puts("abc" <= Plain.new) }
report_msg { puts("abc" > Plain.new) }
report_msg { puts("abc" >= Plain.new) }
p("abc" == Wrap.new("abc"))
p("abc".eql?(Wrap.new("abc")))
p("abc" <=> :abc)
p("abc" <=> 1)
report_msg { puts("abc" < :abc) }

# an object-typed slot holding nil: nothing to ask for #to_str, and CRuby
# names it "nil"
def maybe_wrap(flag)
  return nil unless flag
  Wrap.new("abd")
end

p("abc" < maybe_wrap(true))
p("abc" <=> maybe_wrap(false))
report_msg { puts("abc" < maybe_wrap(false)) }

plains = [Plain.new, 1]
bp = plains[0]
p("abc" <=> bp)
p("abc".casecmp(bp))
report { puts("abc" < bp) }

# --- #to_str runs exactly once per comparison, and #between? stops at the
#     first bound the way CRuby's two <=>s do ---
$calls = []

class Counted
  def initialize(s)
    @s = s
  end

  def to_str
    $calls << @s
    @s
  end
end

("abc" <=> Counted.new("abd"))
p $calls
$calls = []
("abc" < Counted.new("abd"))
p $calls
$calls = []
"abc".between?(Counted.new("aaa"), Counted.new("abd"))
p $calls
$calls = []
"abc".between?(Counted.new("zzz"), Counted.new("abd"))
p $calls

# --- a mixed #between?: CRuby stops at the first <=>, so a bound that
#     answers no #to_str is never asked when the first bound settled it ---
$calls = []
p("abc".between?(Counted.new("abd"), Plain.new))
p $calls
$calls = []
report_msg { puts("abz".between?(Counted.new("aaa"), Plain.new)) }
p $calls
$calls = []
report_msg { puts("abc".between?(Plain.new, Counted.new("abz"))) }
p $calls

# --- a BOXED #between? bound beside a typed one: it asks the runtime's
#     rb_check_string_type, as a boxed operand does anywhere else, so a slot
#     holding a String or a converting object compares and any other value is
#     the comparison error, named after what the slot actually held ---
boxed_hi = ["abz", 1][0]
boxed_lo = ["aaa", 1][0]
boxed_hi_obj = [Wrap.new("abz"), 1][0]
boxed_int = [5, "x"][0]
boxed_nil = [nil, "x"][0]
p("abc".between?(Wrap.new("aaa"), boxed_hi))
p("abz".between?(Wrap.new("aaa"), boxed_hi))
p("abc".between?(boxed_lo, Wrap.new("abz")))
p("abc".between?(Wrap.new("aaa"), boxed_hi_obj))
report_msg { puts("abc".between?(Wrap.new("aaa"), boxed_int)) }
report_msg { puts("abc".between?(Wrap.new("aaa"), boxed_nil)) }

# the boxed hi is never asked for a string when the typed lo already settled it
$calls = []
boxed_counted = [Counted.new("abz"), 1][0]
p("abc".between?(Wrap.new("abd"), boxed_counted))
p $calls

# --- a #to_str typed String that answers the nil String, at all eight ---
p("abc" <=> Maybe.new("abd"))
p("abc" <=> Maybe.new)
p("abc".casecmp(Maybe.new))
p("abc".casecmp?(Maybe.new))
report_msg { puts("abc" < Maybe.new) }
report_msg { puts("abc" <= Maybe.new) }
report_msg { puts("abc" > Maybe.new) }
report_msg { puts("abc" >= Maybe.new) }
report_msg { puts("abc".between?(Maybe.new, Maybe.new)) }

# --- a #to_str typed poly that answers nil, at all eight ---
p("abc" <=> Vague.new("abd", true))
p("abc".casecmp(Vague.new("ABD", true)))
p("abc".casecmp?(Vague.new("ABD", true)))
report_msg { puts("abc" < Vague.new("abd", true)) }
report_msg { puts("abc" <= Vague.new("abd", true)) }
report_msg { puts("abc" > Vague.new("abd", true)) }
report_msg { puts("abc" >= Vague.new("abd", true)) }
report_msg { puts("abc".between?(Vague.new("aaa", true), Vague.new("abd", true))) }
p("abc" <=> Vague.new("abd", false))
p("abc" < Vague.new("abd", false))

# --- a receiver that is itself a converting comparison's ternary ---
p((("abc" < Wrap.new("abd")) ? "abc" : "zzz").casecmp(Wrap.new("ABC")))
p((("abc" < Wrap.new("abd")) ? "abc" : "zzz") < Wrap.new("abd"))

# --- the converted String is held across the compare: a churn loop whose
#     #to_str allocates a fresh answer every round ---
class Churn
  def initialize(n)
    @n = n
  end

  def to_str
    "a" * @n
  end
end

# the operand's own object has to survive its #to_str, which allocates
# before it reads self -- the boxed side reaches the conversion with the
# object held in nothing but the argument
class Popped
  def initialize(s)
    @s = s
  end

  def to_str
    pad = "y" * 64
    @s + pad[0, 0]
  end
end

popped = 0
300.times do
  q = [1, Popped.new("abd")]
  popped += 1 if "abc" < q.pop
end
p popped

churns = [Churn.new(4), 1]
boxed_churn = churns[0]
wrong = 0
300.times do |i|
  wrong += 1 if ("aaaa" <=> Churn.new(4)) != 0
  wrong += 1 unless "#{'a' * 4}".between?(Churn.new(3), Churn.new(5))
  wrong += 1 unless "#{'a' * 4}".casecmp(boxed_churn) == 0
  wrong += 1 unless ("aaaa" + "").casecmp(Churn.new(4)) == 0
end
p wrong
