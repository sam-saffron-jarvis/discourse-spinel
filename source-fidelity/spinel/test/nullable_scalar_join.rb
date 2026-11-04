# nil meeting an Integer or a Float joins to the nullable scalar (int? with
# the SP_INT_NIL sentinel, float? with the NaN payload), not to the boxed
# slow path: a local written nil on one path and a number on another, a nil
# argument to a numeric parameter, a `return nil if` ahead of a number, an
# if with no else, a case no arm matched, a `next nil` in a block, a
# begin/rescue whose rescue arm is nil, a Data member, a global and a class
# ivar left unassigned, and a `<=>` answering nil. Every consumer reads the
# sentinel as nil: p/inspect, nil?, ==, ||= / &&=, Hash keys, boxing.

def w(flag, line)
  if flag
    line.length
  else
    $stdout.puts(line)
  end
end
p w(true, "abc")
p w(false, "xy")

def pick(n)
  return nil if n > 5
  return 7 if n > 3
  9
end
p pick(1), pick(4), pick(9)

def fl(n) = n > 0 ? 1.5 : nil
p fl(1), fl(0)

a = nil
a ||= 10
p a
a ||= 99
p a
b = nil
b &&= 7
p b
c = 5
c &&= 8
p c

x = 3
x = nil if x > 2
p x, x.nil?, x == nil

p ["1", "x"].map { |s| Integer(s) rescue nil }
p [1, 2, 3].map { |v| next nil if v == 2; v * 10 }

v = begin; 1; rescue; 2; else; nil; end
p v

def cs(n)
  case n
  when 1 then 10
  when 2 then 20
  end
end
p cs(1), cs(3)

def f(x) = x
p f(1), f(nil)

class C
  def initialize(a); @a = a; end
  attr_reader :a
end
p C.new(nil).a, C.new(3).a

Pt = Data.define(:v)
p Pt.new(nil), Pt.new(2).v, Pt.new(nil).v

$g = nil
p $g
$g = 2.5
p $g
class K
  def self.set; @v = 2.5; end
  def self.get; @v; end
end
p K.get
K.set
p K.get

h = {}
k = f(nil)
h[k] = "var"
p h[nil], h.key?(nil)
m = { k => 1, nil => 2 }
p m.length

g = ->(arr) { arr.each { |e| return e if e > 2 }; nil }
p g.call([1, 2, 3]), g.call([1, 1])

def m2(arr)
  arr.each { |e| r = yield e; p r }
end
m2([1, 2]) { |i| next 7 if i == 1; nil }
def cnt(arr)
  n = 0
  arr.each { |e| n += 1 if yield e }
  n
end
p cnt([1, 2]) { |i| next 7 if i == 1; nil }

class Ver
  include Comparable
  attr_reader :n
  def initialize(n); @n = n; end
  def <=>(o); o.n < 0 ? nil : (n <=> o.n); end
end
p Ver.new(1) < Ver.new(2)
begin
  Ver.new(1) < Ver.new(-1)
rescue ArgumentError => e
  puts "AE: #{e.message}"
end
p [1, 3, 7, 9, 12].bsearch { |e| e < 9 ? nil : (e == 9 ? 0 : -1) }

def need(s)
  return false unless s.is_a?(String)
  s.start_with?("h")
end
p need("hi"), need(nil)
begin
  f(nil).scan(/x/)
rescue NoMethodError => e
  puts "NME: #{e.message}"
end
def nn(x) = x.nil? ? "none" : x + 1
p nn(1), nn(nil)
