# An instance of a Struct.new class is a Struct, an instance of a Data.define
# class is a Data, in a case arm as it already was in is_a?: the class table
# records the builtin above the user class, and the arm reads that row.
Point = Struct.new(:x, :y)
class Pair < Struct.new(:a, :b); end
class Named < Point; end
Coord = Data.define(:lat, :lng)
class Fixed < Coord; end
class Plain; end

def point(f) = f ? Point.new(1, 2) : nil

pt = Point.new(1, 2)
pr = Pair.new(3, 4)
nm = Named.new(5, 6)
co = Coord.new(lat: 7, lng: 8)
fx = Fixed.new(lat: 9, lng: 10)
pl = Plain.new

puts(case pt; in Struct then "in-struct"; else "other"; end)
puts(case pt; when Struct then "when-struct"; else "other"; end)
puts((case pt; when Struct then "expr-struct"; else "other"; end))
case pt
when Struct then puts "stmt-struct"
else puts "stmt-other"
end
case co
in Data then puts "stmt-data"
in Struct then puts "stmt-struct"
end
puts(case pt; in Data then "in-data"; else "other"; end)
puts(case pr; when Struct then "pair-struct"; else "other"; end)
puts(case nm; in Struct then "named-struct"; else "other"; end)
puts(case co; in Data then "in-data"; else "other"; end)
puts(case co; when Data then "when-data"; else "other"; end)
puts(case co; in Struct then "in-struct"; else "other"; end)
puts(case fx; when Data then "fixed-data"; else "other"; end)
puts(case pl; in Struct then "in-struct"; else "other"; end)
puts(case pt; when Data, Struct then "either"; else "other"; end)
puts(case pt; in Struct | Data then "either"; else "other"; end)
r = (pt in Struct); puts r
r = (co in Data); puts r
r = (pt in Data); puts r
puts(case pt; in Struct[x, y] then "fields #{x} #{y}"; else "other"; end)
puts(case pt; in Point then "point"; else "other"; end)
puts(case pt; in Object then "object"; else "other"; end)
[pt, co, pl, 5].each { |v| print(case v; in Struct then "S"; in Data then "D"; else "-"; end) }
puts
[pt, co, pl].each { |v| print(v.is_a?(Struct) ? "S" : "-") }
puts
[pt, co, pl].each { |v| print(case v; when Data then "D"; else "-"; end) }
puts
q = point(false)
puts(case q; in Struct then "in-struct"; else "other"; end)
puts(case q; when Struct then "when-struct"; else "other"; end)
