# The poly `&`, `|`, `^` and `>>` arms boxed their receiver inline as the
# first C argument of sp_poly_bitop / sp_poly_shr and the operand as the
# second, so a receiver held by nothing else (a fresh array, a fresh user
# object, a Bignum) was freed when the operand allocated, and which
# argument ran first was the C compiler's choice. Built from dfbfb5aa, the
# first ten loops below count wrong results in 200 of 200 under
# SPINEL_GC_STRESS=1; loops 9 and 10, whose operand reassigns the slot the
# receiver was read from, are wrong in 200 of 200 in the plain build too,
# because the operand ran first. The last loop, a local receiver with a
# non-allocating operand, is right on both.
class Bits
  attr_reader :v
  def initialize(v) @v = v end
  def >>(o) Bits.new(@v - o) end
  def &(o) Bits.new(@v * o) end
  def |(o) Bits.new(@v + o) end
  def ^(o) Bits.new(@v - o) end
end

def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  nil
end

def churn_obj
  (1..30).map { |i| Bits.new(i) }
  (1..30).map { |i| "t#{i}" }
  nil
end

def mka(n)
  return "s#{n}" if n < 0
  [1, "a", n]
end

def mku(n)
  return "s#{n}" if n < 0
  Bits.new(n)
end

def mkb(n)
  return "s#{n}" if n < 0
  1267650600228229401496703205376 + n
end

class Holder
  def initialize; @a = mka(1); end
  def reset; @a = mka(9); end
  def go
    @a & (reset; churn; mka(9))
  end
end

bad = [0] * 11
200.times do
  bad[0] += 1 if (mka(1) & (churn; mka(1))) != [1, "a"]
  bad[1] += 1 if (mka(1) | (churn; mka(3))) != [1, "a", 3]
  bad[2] += 1 if (mku(7) >> (churn_obj; 2)).v != 5
  bad[3] += 1 if (mku(7) & (churn_obj; 2)).v != 14
  bad[4] += 1 if (mku(7) | (churn_obj; 2)).v != 9
  bad[5] += 1 if (mku(7) ^ (churn_obj; 3)).v != 4
  bad[6] += 1 if ((mka(1) & (churn; mka(1))) | (churn; mka(2))) != [1, "a", 2]
  bad[7] += 1 if (mkb(1) >> (churn; 1)) != 633825300114114700748351602688
  x = mka(1)
  bad[8] += 1 if (x & (x = mka(5); churn; mka(5))) != [1, "a"]
  bad[9] += 1 if Holder.new.go != [1, "a"]
  y = mku(9); n = 4
  bad[10] += 1 if (y | n).v != 13
end
p bad
