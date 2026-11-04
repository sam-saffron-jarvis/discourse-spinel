# A global whose only assignment is nil, or which is never assigned at all,
# must read back as nil. The int-typed slot started at 0 and wrote 0 for an
# explicit nil, so `if $g` took the truthy branch and `-$g` was -0: the
# reported shape was `Process.kill("KILL", -$pgid)` signalling the caller's
# own process group (#4248).
$explicit = nil

def assigns_int
  $explicit = 42
end

def read_explicit
  $explicit ? "truthy" : "falsy"
end

p read_explicit
p $explicit.nil?

# never assigned anywhere but in a method that does not run
def assigns_other
  $never = 7
end

p($never ? "truthy" : "falsy")
p $never.nil?

# the guard still passes once a value is actually stored
assigns_int
p read_explicit
p $explicit
p $explicit.nil?

# a genuine zero is truthy, as in Ruby
$zero = 0
p($zero ? "truthy" : "falsy")
p $zero.nil?

# and the negation the report turned on
$pgid = nil
p($pgid ? -$pgid : "no pgid")
$pgid = 123
p($pgid ? -$pgid : "no pgid")

# a string-typed global keeps the convention it already had
$s = nil
p $s.nil?
$s = "x"
p $s
