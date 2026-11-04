class NotAnError
  def initialize(x)
    @x = x
  end
end

obj = NotAnError.new(42)
begin
  raise obj
rescue TypeError => e
  puts "caught: #{e.message}"
end
