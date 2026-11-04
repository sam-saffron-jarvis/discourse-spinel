# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# A big Rational's #to_s builds the numerator's text and then the
# denominator's, and the second conversion allocates, so the first text has
# to stay live across it. Every turn allocates before it asks, and the test
# prints how many answers came back wrong together with the first wrong one,
# so a swept numerator shows up as a changed answer rather than a passing
# test. The Rational is held in a local the whole time: only #to_s is under
# test here, not the constructor.

N = 5000

def churn(i)
  [i.to_s * 3, [i, i + 1]]
end

def check(r, want)
  bad = 0
  first = nil
  N.times do |i|
    churn(i)
    s = r.to_s
    next if s == want
    bad += 1
    first ||= s
  end
  puts "#{want}: bad=#{bad}#{first ? " first=#{first.inspect}" : ""}"
end

check(Rational(10**40, 4), "2500000000000000000000000000000000000000/1")
check(Rational(10**40 + 1, 3), "10000000000000000000000000000000000000001/3")
check(Rational(-(10**30), 7**20), "-1000000000000000000000000000000/79792266297612001")
check(Rational(3, 2**70), "3/1180591620717411303424")

bad = 0
first = nil
r = Rational(10**40, 4)
N.times do |i|
  churn(i)
  s = r.inspect
  next if s == "(2500000000000000000000000000000000000000/1)"
  bad += 1
  first ||= s
end
puts "inspect: bad=#{bad}#{first ? " first=#{first.inspect}" : ""}"

bad = 0
first = nil
N.times do |i|
  churn(i)
  s = "#{r}"
  next if s == "2500000000000000000000000000000000000000/1"
  bad += 1
  first ||= s
end
puts "interpolation: bad=#{bad}#{first ? " first=#{first.inspect}" : ""}"
