# method(:Kernel_builtin) synthesizes a one-parameter __bam_ wrapper whose
# declared shape is NOT the builtin's arity (receiversless: __bam_r is a real
# argument, unlike a receiver-bound wrapper's leading self slot):
#   * Method#arity must report CRuby's real arity (String 1, Integer -2,
#     puts -1, ...), for both a statically-typed Method and one read out of a
#     container (#4395).
#   * The wrapper still evaluates the receiverless builtin: method(:String)
#     .call(123) is "123", and method(:String).call raises ArgumentError rather
#     than invoking the wrapper with an undefined register (#4395).
#   * A variadic builtin's extra arguments are truncated -- the wrapper
#     forwards only the first -- matching the pre-#4395 behavior instead of
#     raising. The snapshot below is hand-written for that last line: CRuby's
#     puts would print both arguments.
p method(:String).arity
p method(:Integer).arity
p method(:Float).arity
p method(:Array).arity
p method(:Rational).arity
p method(:Complex).arity
p method(:puts).arity
p method(:print).arity
p method(:p).arity
p method(:pp).arity

# Read back out of a container: the arity survives as the stamped field.
sa = [method(:String)]
p sa[0].arity
pa = [method(:puts)]
p pa[0].arity

puts method(:String).call(123).inspect
begin
  method(:String).call
rescue => e
  puts "zero: #{e.class}"
end

# The wrapper takes what its call sites pass, so both arguments arrive.
method(:puts).call("a", "b")
puts "after"
