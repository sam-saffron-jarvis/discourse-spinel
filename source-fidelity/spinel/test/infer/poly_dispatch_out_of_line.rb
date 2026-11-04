# A boxed receiver's dispatch over many classes is one static function that
# every site with the same switch calls, not a switch written out at each
# site (#4847).
class Aa; def describe = "aa"; end
class Bb; def describe = "bb"; end
class Cc; def describe = "cc"; end
class Dd; def describe = "dd"; end
class Ee; def describe = "ee"; end
class Ff; def describe = "ff"; end
class Gg; def describe = "gg"; end
xs = [Aa.new, Bb.new, Cc.new, Dd.new, Ee.new, Ff.new, Gg.new]
xs.each { |x| puts x.describe }
puts xs[ARGV.size].describe
