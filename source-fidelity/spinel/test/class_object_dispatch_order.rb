# A class method called on a poly Class slot evaluates its receiver before
# its arguments, as any Ruby call does. The receiver here is a method call
# that logs, and so is the argument; the log names the order.
class A
  def self.hydrate(s)
    s.length
  end
end

class B
  def self.hydrate(s)
    s.length + 1
  end
end

$log = []

class Holder
  def initialize(model)
    @model = model
  end

  def model
    $log << "receiver"
    @model
  end

  def build
    $log << "argument"
    "sql"
  end

  def run
    model.hydrate(build)
  end
end

models = { "a" => A, "b" => B }
puts Holder.new(models["b"]).run
puts $log.join(",")
