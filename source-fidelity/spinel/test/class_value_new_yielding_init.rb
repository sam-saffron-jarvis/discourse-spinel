class A
  def initialize(x) = @x = x
  def to_s = "A(#{@x})"
end

class B
  def initialize(x)
    @x = x
    @y = block_given? ? yield(x) : "none"
  end

  def to_s = "B(#{@x},#{@y})"
end

B.new(9) { |v| v }
[A, B].each { |k| puts({ 0 => k }.fetch(0).new(1)) }
