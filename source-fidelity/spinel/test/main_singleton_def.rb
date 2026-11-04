# A top-level `def self.k` is a singleton method of main; a top-level `def k`
# is Object's private method. On main -- the top-level statements, their
# blocks, the singleton's own body -- `k` and `self.k` reach the singleton;
# from any other object `k` is Object's. Both were emitted as one C function
# (a redefinition), and `self.k` on main raised NoMethodError even alone.
def self.k = :singleton
def k = :plain
p k
p self.k
[1].each { p k }
class A
  def m = k
  def self.cm = new.m
end
p A.new.m
p A.cm

def self.fact(n) = n <= 1 ? 1 : n * self.fact(n - 1)
p self.fact(5)
p fact(4)

def self.only = :only_singleton
p self.only
p only
