# An in-place String mutation whose receiver is a global, a class variable
# or a constant built the new string and dropped it: `$g << "ab"`,
# `x = ($g << "q")` and `S << "d"` all left the receiver as it was. A local
# or ivar receiver is reassigned; these now are too, in statement and value
# position: << and its chains, concat/prepend/insert, the bang methods (with
# and without arguments), replace/clear, and slice!.

# -- global, statement position
$g = +"g"
$g << "ab"
puts $g
$g << "c" << "d"
puts $g
$g.upcase!
puts $g
$g.gsub!("A", "x")
puts $g
$g.replace("r")
$g.prepend("p")
$g.insert(1, "i")
puts $g
$g.clear
puts $g.size
def log(s) = $g << s
log("1")
log("2")
puts $g
$h = String.new
$h << "xy"
puts $h.size

# -- global, value position
$v = +"v"
x = ($v << "q")
puts x.size, $v
puts($v << "w")
puts(($v << "1" << "2").size)
puts $v
p($v.upcase!)
p($v.upcase!)
p($v.sub!("Q", "s"))
p($v.tr!("W", "t"))
p($v.delete_suffix!("12"))
p($v.slice!(0))
p($v.concat("c"))
p($v.insert(0, "I"))
p($v.clear)
puts $v.size
p($v.replace("rep"))
puts $v
$v = +""
def app(s) = ($v << s)
app("m")
app("n")
puts $v

# -- class variable
class C
  @@v = +"v"
  def self.f
    @@v << "ab"
    @@v.upcase!
    @@v
  end
  def g
    @@v << "i"
    @@v.swapcase!
    @@v
  end
  def h
    y = (@@v << "j")
    [y.size, @@v.prepend("P").size, @@v.delete!("i"), @@v]
  end
end
puts C.f
puts C.new.g
p C.new.h

# -- constants
S = +"s"
S << "a"
S << "b" << "c"
puts S
S.upcase!
puts S
p(S << "d")
p(S.downcase!)
p(S.squeeze!)
S.clear
puts S.size
p(S.replace("t"))
T = String.new
T << "t"
puts T
class K
  U = +"u"
  def self.go
    U << "v"
    r = U.upcase!
    [r, U]
  end
end
p K.go
K::U << "w"
p(K::U.sub!("W", "x"))
puts K::U

# -- a frozen constant or global still raises
F = "f".freeze
$fz = "z".freeze
[-> { F << "x" }, -> { F.upcase! }, -> { p(F << "x") }, -> { p(F.replace("y")) },
 -> { $fz << "x" }, -> { p($fz.gsub!("z", "y")) }].each do |l|
  begin
    l.call
  rescue FrozenError => e
    puts e.class
  end
end
puts F, $fz
