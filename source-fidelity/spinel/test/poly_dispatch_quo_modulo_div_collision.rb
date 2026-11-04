# The poly-dispatch collision gap (#4816), the third instance: a poly value
# whose actual class is Integer, Float or Bignum reached NO numeric
# implementation for quo/modulo/div as soon as any class in the program
# defined a method of the same name (the collision-dispatch switch had an
# arm per user class and no default arm for the non-object tags). Same shape
# as divmod/remainder/fdiv (#4816's earlier instances).
class Widget
  def quo(x) = "widget-quo-#{x}"
  def modulo(x) = "widget-modulo-#{x}"
  def div(x) = "widget-div-#{x}"
end

def pick(v) = v

# 1. a contested numeric receiver still answers the numeric operation.
p pick(7).quo(2)
p pick(7).modulo(2)
p pick(7).div(2)
p pick(-7).quo(2)
p pick(-7).modulo(2)
p pick(-7).div(2)
p pick(7.5).quo(2)
p pick(7.5).modulo(2)
p pick(7.5).div(2)
p pick(2**70).modulo(3)
p pick(2**70).div(3)

# 2. the colliding class's own instance still wins.
p pick(Widget.new).quo(2)
p pick(Widget.new).modulo(2)
p pick(Widget.new).div(2)

# 3. a receiver whose class has no such method raises NoMethodError.
begin
  pick(nil).quo(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick(nil).modulo(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick(nil).div(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick(true).quo(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick([1, 2]).modulo(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick({ a: 1 }).div(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick(:sym).quo(2)
rescue NoMethodError => e
  puts e.message
end
begin
  pick("str").div(2)
rescue NoMethodError => e
  puts e.message
end

# 4. a colliding class with a DIFFERENT arity than the call site still wins.
class Gadget
  def quo = "gadget-quo-noarg"
end

def pick2(v) = v
p pick2(9).quo(3)
p pick2(Gadget.new).quo

# 5. the general `%`/`modulo` receiver-guard fix that came out of the same
# runtime helper: a plain (non-collision) poly `%`/`modulo` on a receiver
# with no such method must raise, not silently answer 0.
begin
  pick(nil) % 1
rescue NoMethodError => e
  puts e.message
end
begin
  pick(nil).modulo(1)
rescue NoMethodError => e
  puts e.message
end
begin
  pick([1, 2]) % 1
rescue NoMethodError => e
  puts e.message
end
begin
  pick(true) % 1
rescue NoMethodError => e
  puts e.message
end

# 6. String has `%` but not `modulo` -- the stricter sp_poly_modulo guard.
begin
  pick("x").modulo(1)
rescue NoMethodError => e
  puts e.message
end
p pick("val=%d") % 42

# 7. the numeric coerce protocol through quo/modulo/div/% is unaffected.
class Coin
  def coerce(o) = [o, 5]
end
p pick(3) % Coin.new
p pick(3).quo(Coin.new)
p pick(3).modulo(Coin.new)
p pick(3).div(Coin.new)

# 8. a Rational receiver (forced poly) is unaffected.
p pick(Rational(7, 2)).quo(2)
p pick(Rational(7, 2)).modulo(2)
p pick(Rational(7, 2)).div(2)
p pick(Rational(7, 2)) % 2
