# A value-position case arm ending in an ivar operator-assign spliced its
# #line directive mid-line, after `case 1LL: { `, and the C did not
# compile (#4830).

class S
  def initialize
    @m = 7
    @late = true
  end
  def step(x)
    case x
    when 1 then @m &= 3
    when 2 then @m += 1
    else @m -= 1
    end
  end
  def step2(x)
    r = case x
        when 1 then (@m &= ~1 if @late)
        end
    r
  end
end
s = S.new
p s.step(1)
p s.step(2)
p s.step(9)
p s.step2(1)
