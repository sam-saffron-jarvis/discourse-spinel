# A class method defined on a class WITH subclasses is compiled with a leading
# receiving-class token; a class-value dispatch arm must pass the class its own
# case selected, so an inherited body answers `name` per subclass (#4217).
class Base
  def self.find(id)
    "found #{name} #{id}"
  end
end

class Room < Base
end

class User < Base
  def self.find(id)
    "user-find #{name} #{id}"
  end
end

def locate(only:)
  only.find(7)
end

puts locate(only: Room)
puts locate(only: Base)
puts locate(only: User)

# a leaf class with no descendants keeps the token-less convention
class Leaf
  def self.tag(n)
    "leaf #{n}"
  end
end

def call_tag(k)
  k.tag(3)
end

puts call_tag(Leaf)
