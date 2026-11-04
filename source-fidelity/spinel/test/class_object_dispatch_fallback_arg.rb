# The class-tag dispatch's not-a-Class fallback. When no instance method of
# the name exists anywhere in the program the site compiles through the
# class-tag dispatch alone, and a slot that holds something other than a
# Class at run time falls through to it: NoMethodError, as CRuby raises.
# The fallback renders the same hoisted arguments as the class arms, so
# the argument is evaluated once there too, after the receiver — and the
# next dispatch through the same site, on a Class, starts from a clean
# override stack.
class A
  def self.hydrate(s)
    $log << "A.hydrate"
    s.length
  end
end

class B
  def self.hydrate(s)
    $log << "B.hydrate"
    s.length + 1
  end
end

$log = []

class Holder
  def initialize(slot)
    @slot = slot
  end

  def slot
    $log << "receiver"
    @slot
  end

  def build
    $log << "argument"
    "sql"
  end

  def run
    slot.hydrate(build)
  rescue NoMethodError
    $log << "NoMethodError"
    -1
  end
end

values = { "i" => 42, "a" => A, "b" => B }
puts Holder.new(values["i"]).run
puts $log.join(",")
$log = []
puts Holder.new(values["b"]).run
puts $log.join(",")
$log = []
puts Holder.new(values["i"]).run
puts $log.join(",")
