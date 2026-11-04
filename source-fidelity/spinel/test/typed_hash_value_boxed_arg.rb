# value? on a typed Hash with a boxed argument compares boxed values (#4939)
INTERVALS = { "d" => "Day", "w" => "Week" }.freeze

class Opt
  def [](k) = "week"
end

def ok?(length) = INTERVALS.value?(length[:intv].capitalize)

p ok?({ intv: "day" })
p ok?(Opt.new)
p ok?({ intv: "month" })
NUMS = { "a" => 1, "b" => 2 }
def has?(x) = NUMS.value?(x)
p has?(2), has?("2"), has?(nil)
