# A raise drops the handler-stack entries opened inside the frame it lands in:
# the catch entries it unwinds past, and the break scopes and proc-return homes
# it unwinds past at every landing, including the ones that never pruned them.
# The 200-round counts are the teeth -- the stacks hold 64, so a leaked entry
# per round runs off the end around round 65 -- but the throw below diverges on
# the very first round without any repetition.

# a raise out of a catch, rescued outside it
c = 0
200.times do
  begin
    catch(:x) { raise ArgumentError, "boom" }
  rescue ArgumentError
    c += 1
  end
end
puts c

# the entry that raise dropped must not answer a later throw: this one has no
# live catch left, so it is an uncaught throw
begin
  catch(:y) do
    begin
      catch(:x) { raise "e" }
    rescue RuntimeError
    end
    throw :x
  end
  puts "the throw was delivered to a finished catch"
rescue UncaughtThrowError => e
  puts e.message
end

# a throw from an ensure running while an exception unwinds still finds its
# catch -- once with nothing around the catch, once inside a rescue
r = catch(:x) do
  begin
    raise "e"
  ensure
    throw :x, 7
  end
end
p r
begin
  r = catch(:x) do
    begin
      raise "e"
    ensure
      throw :x, 8
    end
  end
  p r
rescue => e
  puts "escaped as #{e.class}"
end

# the same raise out of a catch inside Kernel#loop, which lands in its own frame
c = 0
200.times do
  loop do
    begin
      catch(:x) { raise ArgumentError, "boom" }
    rescue ArgumentError
      c += 1
    end
    raise StopIteration
  end
end
puts c

# a raise unwinding past a proc-return home, and a return that must still reach
# a live one afterwards
def call_block
  yield
end
c = 0
200.times do
  begin
    call_block { catch(:x) { raise "e" } }
  rescue RuntimeError
    c += 1
  end
end
puts c
def first_over_one(a)
  a.each { |x| return x if x > 1 }
  nil
end
p first_over_one([1, 2, 3])

# a break scope opened inside the frame a StopIteration lands in
n = 0
200.times do
  loop do
    [1].each { |x| break 5 if x == 9; raise StopIteration }
  end
  n += 1
end
puts n

# and the same in Kernel#loop's expression form, whose landing is a different
# one: the loop's value is the exhausted iteration's result
n = 0
200.times do
  v = loop do
    [1].each { |x| break 5 if x == 9; raise StopIteration }
  end
  n += 1 if v.nil?
end
puts n
