# A parameter's default reading a poly ivar widens the parameter, even when
# the only call site passing it explicitly passes one concrete class.

class Wood
  def sound = "knock"
end
class Glass
  def sound = "clink"
end
class Tin
  def sound = "tink"
end

# a positional default
class Striker
  def initialize(target)
    @target = target
    @spare = Glass.new
    @current = @target
  end

  def swap(flag)
    flag ? aim(@spare) : aim
  end

  def aim(t = @target)
    @current = t
  end

  def hit = @current.sound
end

[Striker.new(Wood.new), Striker.new(Tin.new)].each do |s|
  [true, false].each do |f|
    s.swap(f)
    puts s.hit
  end
end

# a keyword default among several keywords, read after the call returns
class Mixer
  def initialize(src)
    @src = src
    @alt = Tin.new
  end

  def pick(alt) = alt ? pour(into: @alt, n: 2) : pour(n: 1)

  def pour(into: @src, n: 1) = "#{into.sound}x#{n}"
end

[Mixer.new(Wood.new), Mixer.new(Glass.new)].each do |m|
  puts m.pick(true)
  puts m.pick(false)
end
