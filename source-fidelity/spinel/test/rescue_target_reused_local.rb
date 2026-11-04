# A local that also holds an ordinary value keeps it when a rescue arm
# binds the same name (#4923)
class Foo
  attr_accessor :x
end
class MyErr < StandardError; end

e = Foo.new
e.x = 5
p e.x
begin
  raise "boom"
rescue RuntimeError => e
  p e.message
end
p e.class

def m
  v = 1
  p v + 1
  begin
    raise MyErr, "mine"
  rescue MyErr => v
    p v.message
  rescue => v
    p [:other, v.message]
  end
  v = "after"
  p v
end
m
