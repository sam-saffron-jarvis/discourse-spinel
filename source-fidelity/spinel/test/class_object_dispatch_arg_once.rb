# A class method called on a poly slot holding a Class (`@model.hydrate(…)`,
# the #3215 shape) dispatches on the class tag, one arm per candidate
# class. Each arm rendered the call's arguments for its own callee, so an
# argument that is an EXPRESSION was evaluated once per candidate — and
# again for the not-a-Class fallback — rather than once. Here `build`
# counts its calls: Ruby says 1 for three candidate classes.
class A
  def self.cols
    "a.x"
  end

  def self.hydrate(s)
    s.length
  end
end

class B
  def self.cols
    "b.x, b.y"
  end

  def self.hydrate(s)
    s.length + 1
  end
end

class C
  def self.cols
    "c.x, c.y, c.z"
  end

  def self.hydrate(s)
    s.length + 2
  end
end

class Holder
  def initialize(model)
    @model = model
  end

  def build(cols)
    $builds += 1
    "SELECT #{cols}"
  end

  def run
    @model.hydrate(build(@model.cols))
  end
end

models = { "a" => A, "b" => B, "c" => C }
$builds = 0
puts Holder.new(models["a"]).run
puts "build called #{$builds} time(s)"
$builds = 0
puts Holder.new(models["c"]).run
puts "build called #{$builds} time(s)"
