# `klass === x` with the class carried as a value (a parameter, a local, an
# element read) rather than written as a constant at the call site: the
# literal form folds on the name, this form asks the operand's class at run
# time. A builtin class, a user class and its subclass, a module, Object,
# nil and a class out of an array all answer as CRuby does.
class Animal; end
class Dog < Animal; end
module Walks; end
class Cat < Animal; include Walks; end
def sel(a, pattern)
  out = []
  a.each { |x| out << x if pattern === x }
  out
end
items = [1, "a", 2.5, :s, nil, Dog.new, Cat.new, [1], { a: 1 }]
[Integer, String, Float, Symbol, Numeric, Comparable, NilClass, Animal, Dog, Cat, Walks, Object, Array, Hash].each do |k|
  puts "#{k}: #{sel(items, k).map { |x| x.is_a?(Animal) ? x.class.name : x.inspect }.join(", ")}"
end
def which(x, *klasses) = klasses.find { |k| k === x }
p which(3, String, Integer)
p which("s", Integer, String)
p which(Dog.new, Cat, Animal)
p which(2.5, Integer, String)
k = [Integer, String][1]
p k === "x", k === 1
def check(pattern, x) = pattern === x
p check(Integer, 5), check(String, 5), check(Animal, Cat.new)
