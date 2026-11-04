# A bare `new` in an inherited class method constructs the CALLING class, so
# `Closed.create!` is specialized for Closed. Reached through a second
# inherited class method (`Closed.create_for` -> `create!` -> `new`) the
# outer method's own body has no `new`, nothing chose to specialize it, and
# its bare call resolved in Room's chain: a Room came back, silently. A class
# method that calls a sibling needing specialization needs it too. (#4427)
class Room
  attr_reader :attrs
  def initialize(attrs = {})
    @attrs = attrs
  end
  def self.create!(attributes = {}) = new(attributes)
  def self.create_for(name)
    create!("name" => name)
  end
  def self.tx
    yield
  end
  def self.build_in_tx(name)
    tx do
      create!("name" => name)
    end
  end
  def kind = "room"
end
class Closed < Room
  def kind = "closed"
end
class Open < Room
  def kind = "open"
end
puts Room.create_for("a").kind
puts Closed.create_for("b").kind
puts Open.create_for("c").kind
puts Closed.create!.kind
puts Closed.build_in_tx("d").kind
puts Room.build_in_tx("e").kind
r = [Room, Closed, Open].map { |k| k.create_for("x").kind }
p r
