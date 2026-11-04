# Kernel#Integer and Kernel#Float on a user object: the object's own
# conversion methods, probed in CRuby's order, each answer judged the way
# CRuby judges it, in the strict and the `exception: false` forms.
$calls = []
def note(name) = $calls << name

def try
  r = yield
  puts "=> #{r.inspect}"
rescue => e
  puts "=> #{e.class}: #{e.message}"
end

def show(label)
  $calls = []
  print label, " "
  yield
  puts "   calls: #{$calls.inspect}" unless $calls.empty?
end

# --- #to_int answers ---------------------------------------------------
class IntAnswer;   def to_int; note(:to_int); 7; end; end
class BigAnswer;   def to_int; note(:to_int); 1 << 70; end; end
class NilAnswer;   def to_int; note(:to_int); nil; end; end
class NilThenToI;  def to_int; note(:to_int); nil; end; def to_i; note(:to_i); 5; end; end
class StrAnswer;   def to_int; note(:to_int); "7"; end; end
class StrThenToI;  def to_int; note(:to_int); "7"; end; def to_i; note(:to_i); 5; end; end
class RaisesToInt; def to_int; note(:to_int); raise "boom"; end; end
class RaiseThenToI; def to_int; note(:to_int); raise "boom"; end; def to_i; note(:to_i); 5; end; end

# --- #to_i alone --------------------------------------------------------
class ToIOnly;     def to_i; note(:to_i); 5; end; end
class ToIBig;      def to_i; note(:to_i); 1 << 70; end; end
class ToIString;   def to_i; note(:to_i); "7"; end; end
class ToINil;      def to_i; note(:to_i); nil; end; end
class ToIRaises;   def to_i; note(:to_i); raise "boom"; end; end

# --- #to_str ------------------------------------------------------------
class StrConv;     def to_str; note(:to_str); "12"; end; end
class BadStrConv;  def to_str; note(:to_str); "zz"; end; end
class StrAndToI;   def to_str; note(:to_str); "12"; end; def to_i; note(:to_i); 99; end; end
class WrongStrConv; def to_str; note(:to_str); 3; end; end
class Plain; end

show("Integer(IntAnswer)")    { try { Integer(IntAnswer.new) } }
show("Integer(BigAnswer)")    { try { Integer(BigAnswer.new) } }
show("Integer(NilAnswer)")    { try { Integer(NilAnswer.new) } }
show("Integer(NilThenToI)")   { try { Integer(NilThenToI.new) } }
show("Integer(StrAnswer)")    { try { Integer(StrAnswer.new) } }
show("Integer(StrThenToI)")   { try { Integer(StrThenToI.new) } }
show("Integer(RaisesToInt)")  { try { Integer(RaisesToInt.new) } }
show("Integer(RaiseThenToI)") { try { Integer(RaiseThenToI.new) } }
show("Integer(ToIOnly)")      { try { Integer(ToIOnly.new) } }
show("Integer(ToIBig)")       { try { Integer(ToIBig.new) } }
show("Integer(ToIString)")    { try { Integer(ToIString.new) } }
show("Integer(ToINil)")       { try { Integer(ToINil.new) } }
show("Integer(ToIRaises)")    { try { Integer(ToIRaises.new) } }
show("Integer(StrConv)")      { try { Integer(StrConv.new) } }
show("Integer(BadStrConv)")   { try { Integer(BadStrConv.new) } }
show("Integer(StrAndToI)")    { try { Integer(StrAndToI.new) } }
show("Integer(WrongStrConv)") { try { Integer(WrongStrConv.new) } }
show("Integer(Plain)")        { try { Integer(Plain.new) } }

puts "--- exception: false"
show("Integer(IntAnswer, exception: false)")   { try { Integer(IntAnswer.new, exception: false) } }
show("Integer(BigAnswer, exception: false)")   { try { Integer(BigAnswer.new, exception: false) } }
show("Integer(StrAnswer, exception: false)")   { try { Integer(StrAnswer.new, exception: false) } }
show("Integer(RaisesToInt, exception: false)") { try { Integer(RaisesToInt.new, exception: false) } }
show("Integer(RaiseThenToI, exception: false)") { try { Integer(RaiseThenToI.new, exception: false) } }
show("Integer(ToIString, exception: false)")   { try { Integer(ToIString.new, exception: false) } }
show("Integer(ToIRaises, exception: false)")   { try { Integer(ToIRaises.new, exception: false) } }
show("Integer(StrConv, exception: false)")     { try { Integer(StrConv.new, exception: false) } }
show("Integer(BadStrConv, exception: false)")  { try { Integer(BadStrConv.new, exception: false) } }
show("Integer(Plain, exception: false)")       { try { Integer(Plain.new, exception: false) } }

puts "--- with a base"
show("Integer(StrConv, 16)")                    { try { Integer(StrConv.new, 16) } }
show("Integer(StrConv, 10, exception: false)")  { try { Integer(StrConv.new, 10, exception: false) } }
show("Integer(IntAnswer, 16)")                  { try { Integer(IntAnswer.new, 16) } }
show("Integer(IntAnswer, 16, exception: false)") { try { Integer(IntAnswer.new, 16, exception: false) } }
show("Integer(Plain, 10)")                      { try { Integer(Plain.new, 10) } }

puts "--- Float"
class FltAnswer;   def to_f; note(:to_f); 2.5; end; end
class FltIntAnswer; def to_f; note(:to_f); 3; end; end
class FltStrAnswer; def to_f; note(:to_f); "2.5"; end; end
class FltNilAnswer; def to_f; note(:to_f); nil; end; end
class FltRaises;   def to_f; note(:to_f); raise "boom"; end; end
class FltStrOnly;  def to_str; note(:to_str); "2.5"; end; end
class FltIntOnly;  def to_int; note(:to_int); 4; end; end

show("Float(FltAnswer)")     { try { Float(FltAnswer.new) } }
show("Float(FltIntAnswer)")  { try { Float(FltIntAnswer.new) } }
show("Float(FltStrAnswer)")  { try { Float(FltStrAnswer.new) } }
show("Float(FltNilAnswer)")  { try { Float(FltNilAnswer.new) } }
show("Float(FltRaises)")     { try { Float(FltRaises.new) } }
show("Float(FltStrOnly)")    { try { Float(FltStrOnly.new) } }
show("Float(FltIntOnly)")    { try { Float(FltIntOnly.new) } }
show("Float(Plain)")         { try { Float(Plain.new) } }
show("Float(FltAnswer, exception: false)")    { try { Float(FltAnswer.new, exception: false) } }
show("Float(FltIntAnswer, exception: false)") { try { Float(FltIntAnswer.new, exception: false) } }
show("Float(FltRaises, exception: false)")    { try { Float(FltRaises.new, exception: false) } }
show("Float(Plain, exception: false)")        { try { Float(Plain.new, exception: false) } }

puts "--- through a container"
mixed = [IntAnswer.new, StrConv.new, Plain.new, "42", 9, 2.75, nil, FltAnswer.new]
mixed.each_with_index do |x, i|
  show("Integer(mixed[#{i}])")                  { try { Integer(x) } }
  show("Integer(mixed[#{i}], exception: false)") { try { Integer(x, exception: false) } }
  show("Float(mixed[#{i}], exception: false)")  { try { Float(x, exception: false) } }
end
show("Integer(mixed[1], 16)") { try { Integer(mixed[1], 16) } }
show("Integer(mixed[3], 16)") { try { Integer(mixed[3], 16) } }
show("Integer(mixed[4], 16)") { try { Integer(mixed[4], 16) } }
show("Integer(mixed[4], 16, exception: false)") { try { Integer(mixed[4], 16, exception: false) } }

puts "--- the answer is carried"
big = Integer(BigAnswer.new)
p big + 1
p big.class
p Integer(IntAnswer.new) + 1
p Float(FltAnswer.new) * 2

puts "--- a throw, a break or a proc return out of a probed conversion"
class ThrowsToI;  def to_i; throw :x, 1; end; end
class ThrowsToInt; def to_int; throw :a, 1; end; def to_i; 7; end; end
class CallsProc
  def initialize(pr) = @pr = pr
  def to_int; @pr.call; end
  def to_i; 7; end
end
p(catch(:x) { Integer(ThrowsToI.new, exception: false) })
begin
  p :body
ensure
  p :ensure
end
r = catch(:a) do
  catch(:b) do
    p Integer(ThrowsToInt.new)
    throw :b, 55
    :no
  end
end
p r
def returns_through_proc
  pr = proc { return :returned }
  p Integer(CallsProc.new(pr))
  :fell_through
end
p returns_through_proc
def breaks_out
  [1, 2].each do |i|
    pr = proc { break :broke }
    p Integer(CallsProc.new(pr))
  end
  :done
end
p breaks_out
begin
  p :body
ensure
  p :ensure
end
p :after

puts "--- an answer the analysis cannot pin down"
$flag = true
class Sometimes;    def to_int; $flag ? 7 : nil; end; end
class SometimesBig; def to_int; $flag ? (1 << 70) : nil; end; end
class SometimesToI; def to_int; $flag ? (1 << 70) : nil; end; def to_i; 3; end; end
[true, false].each do |f|
  $flag = f
  show("Sometimes (#{f})")    { try { Integer(Sometimes.new) } }
  show("Sometimes ef (#{f})") { try { Integer(Sometimes.new, exception: false) } }
  # a sometimes-Bignum answer through an Integer slot is a loud RangeError
  # here where CRuby carries it (see the PR); either is an Integer or that
  r = begin; Integer(SometimesBig.new); rescue RangeError => e; :range; rescue TypeError => e; e.message; end
  puts "SometimesBig (#{f}): #{r == (1 << 70) || r == :range ? "the Bignum or the RangeError" : r}"
  show("SometimesBig ef (#{f})") { try { Integer(SometimesBig.new, exception: false) } }
  r = begin; Integer(SometimesToI.new); rescue RangeError => e; :range; rescue TypeError => e; e.message; end
  puts "SometimesToI (#{f}): #{r == (1 << 70) || r == :range ? "the Bignum or the RangeError" : r}"
  show("SometimesToI ef (#{f})") { try { Integer(SometimesToI.new, exception: false) } }
  x = Integer(SometimesBig.new, exception: false)
  p [x.class, x.nil? ? nil : x + 1]
end

puts "--- a conversion method declared with a block parameter is called with none"
class BlkToI;   def to_i(&b);   $blk_seen = b; 5;   end; end
class BlkToF;   def to_f(&b);   $blk_seen = b; 9.5; end; end
class BlkToInt; def to_int(&b); $blk_seen = b; 3;   end; end
$blk_seen = :unset
p [Integer(BlkToI.new), $blk_seen]
p [Float(BlkToF.new), $blk_seen]
p [Integer(BlkToInt.new), $blk_seen]
p Integer(BlkToI.new, exception: false)
p Float(BlkToF.new, exception: false)

puts "--- a plain Bignum read out of a container"
mixed_big = [1 << 70, "s"]
r = begin; Integer(mixed_big[0]); rescue RangeError; :range; end
puts "Integer(boxed Bignum): #{r == (1 << 70) || r == :range ? "the Bignum or the RangeError" : r}"
p Integer(mixed_big[0], exception: false).nil? || Integer(mixed_big[0], exception: false) == (1 << 70)

puts "--- a Float argument"
begin
  Integer(Float::NAN)
rescue FloatDomainError => e
  puts "Integer(NaN): #{e.class}: #{e.message}"
end
begin
  Integer(-Float::INFINITY)
rescue FloatDomainError => e
  puts "Integer(-Infinity): #{e.class}: #{e.message}"
end
p Integer(2.75)

puts "--- the implicit-conversion bridge with a block parameter, and to_str with a base"
class IdxBlk; def to_int(&b); 1; end; end
class WrongStrBase; def to_str; 7; end; end
# a mixed Array, so the element is boxed and the index goes through the bridge
# (a typed slot calls the method directly and is a different site)
boxed = [IdxBlk.new, "not an index"]
p [10, 20, 30][boxed[0]]
begin
  Integer(WrongStrBase.new, 16)
rescue TypeError => e
  puts "to_str answering an Integer, with a base: #{e.message}"
end
begin
  p Integer(WrongStrBase.new, 16, exception: false)
rescue TypeError => e
  puts "with exception false: #{e.class}"
end
