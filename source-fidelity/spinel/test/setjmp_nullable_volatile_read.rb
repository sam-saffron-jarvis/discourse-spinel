# Nullable numeric stack slots keep both members after setjmp/longjmp. A
# by-value volatile struct read may otherwise reuse a pre-setjmp temporary in
# Clang; scalar reads and the old-value capture of op-assignment must reload.
def int_step(seed)
  value = nil
  value = seed if seed
  begin
    value += 2
    raise "stop"
  rescue
    value = value.nil? ? -1 : value + 3
  end
  value
end

def float_rhs
  GC.start
  1.25
end

def float_step(seed)
  value = nil
  value = seed if seed
  begin
    value += float_rhs
    raise "stop"
  rescue
    value = value.nil? ? -1.0 : (value += float_rhs)
  end
  value
end

p int_step(5), int_step(nil)
p float_step(2.5), float_step(nil)
step = lambda do |value|
  begin
    value += 2.0
    raise "stop"
  rescue
    value += 3.0
  end
  value
end
p step.call(1.5)
