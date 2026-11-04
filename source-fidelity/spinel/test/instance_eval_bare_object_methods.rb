# Inside an instance_eval / instance_exec block self is the receiver, so a
# receiverless Object method there asks the receiver. A user method already
# resolved that way; `is_a?`, `respond_to?` and the rest of Object's own
# had no receiver to ask and were refused at compile time.

class Box
  def initialize = @v = 1
  def v = @v
  def to_s = "box"
end

b = Box.new
p b.instance_eval { is_a?(Box) }
p b.instance_eval { is_a?(Integer) }
p b.instance_eval { kind_of?(Object) }
p b.instance_eval { instance_of?(Box) }
p b.instance_eval { respond_to?(:v) }
p b.instance_eval { respond_to?(:nope) }
p b.instance_eval { frozen? }
p b.instance_eval { nil? }
p b.instance_eval { instance_variable_get(:@v) }
p b.instance_eval { equal?(b) }
p b.instance_exec(2) { |n| v + n }
# a user method of the same name still answers
p b.instance_eval { to_s }
