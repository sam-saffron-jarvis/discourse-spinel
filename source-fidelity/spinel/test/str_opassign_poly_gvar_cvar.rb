# `+=` on a String global or class variable whose right side is poly (a
# Symbol-keyed hash value) passed the sp_RbVal straight into sp_str_concat /
# sp_str_plus: the C did not compile. The local arm already coerced it
# (#2875). Statement and value positions, and CRuby's TypeError for nil.
h = { a: "ab", n: 1 }
$g = +"g"
$g += h[:a]
puts $g
x = ($g += h[:a])
puts x
class C
  @@v = +"v"
  def self.f(h)
    @@v += h[:a]
    @@v
  end
  def self.g(h)
    y = (@@v += h[:a])
    y
  end
end
puts C.f(h)
puts C.g(h)
begin
  $g += h[:missing]
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
puts $g
