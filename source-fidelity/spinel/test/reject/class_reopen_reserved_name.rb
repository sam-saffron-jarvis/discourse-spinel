# The compiler carries a reopening of Class under the constant name
# Class__reopen; a program that declares that name itself is refused rather
# than having its declaration taken for the reopening.
class Class__reopen
  def hi = 1
end
class Class
  def ho = 2
end
class Foo; end
p Foo.ho
