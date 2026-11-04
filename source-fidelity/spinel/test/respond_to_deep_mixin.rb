# respond_to? for a name a class answers through Enumerable reached ten
# include levels deep. The mix-in walk stopped at a fixed depth of eight and
# answered false there (from the review of #5090); the class count bounds it.
module M0; include Enumerable; end
module M1; include M0; end
module M2; include M1; end
module M3; include M2; end
module M4; include M3; end
module M5; include M4; end
module M6; include M5; end
module M7; include M6; end
module M8; include M7; end
module M9; include M8; end
module M10; include M9; end
class Bag
  include M10
  def each
    yield 1
    yield 2
  end
end
b = Bag.new
p b.respond_to?(:map)
p [b, 0][0].respond_to?(:map)
p b.map { |x| x * 2 }
