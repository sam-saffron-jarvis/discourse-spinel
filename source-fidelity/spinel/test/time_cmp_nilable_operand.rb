# A Time compared against a `Time | nil` local past its nil guard: the
# operand is boxed, and it is a Time or not at run time (#4465). A
# comparison against a boxed non-Time raises as Comparable does.
def later(timeout)
  deadline = timeout.nil? ? nil : Time.now + timeout
  deadline
end
def expired?(deadline)
  return false if deadline.nil?
  Time.now >= deadline
end
p expired?(later(5))
p expired?(later(-5))
p expired?(later(nil))
d = later(5)
p d.nil?
p d.class
p Time.now >= d unless d.nil?
p Time.now < d, Time.now > d, Time.now <= d
x = [1, "a"]
begin
  p Time.now < x[0]
rescue ArgumentError => e
  puts "ArgumentError"
end
p((Time.now <=> d).class)
