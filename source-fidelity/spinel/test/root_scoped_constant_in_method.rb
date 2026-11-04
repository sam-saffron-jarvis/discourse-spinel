# A constant spelled with a leading scope operator (`::ENV`, `::File`) is the
# top-level constant. Inside a method the rooted spelling typed the receiver
# unknown, so `::ENV.fetch` raised NoMethodError at run time and `::File` /
# `::Math` calls were refused; the bare spelling worked. The rooted form is
# what build scripts write for builtins, so every form must answer as the
# bare one does.
def with_colons = ::ENV.fetch("SPINEL_NOPE", false)
def without_colons = ENV.fetch("SPINEL_NOPE", false)
p without_colons
p with_colons

def base = ::File.basename("a/b.rb")
p base
def root(x) = ::Math.sqrt(x)
p root(4.0)
def isqrt = ::Integer.sqrt(17)
p isqrt
def pat = ::Regexp.new("a+")
p(pat =~ "xaa")

class Foo
  X = 3
  def self.make = new
end
def nested = ::Foo::X
p nested
p ::Foo.make.class

def rescued
  raise ::StandardError, "e"
rescue ::StandardError => e
  e.message
end
p rescued

def klass(v)
  case v
  when ::Integer then "int"
  when ::String then "str"
  else "other"
  end
end
p klass(1), klass("s"), klass(1.5)
p 5.is_a?(::Integer)

::ROOTED = 7
p ROOTED
p ::ROOTED

# A name a class or module body defines keeps the distinction: there the
# rooted spelling is the only way to say "the top-level one".
module Shadowed
  def self.who = "top"
end
module Wrapper
  module Shadowed
    def self.who = "nested"
  end
  def self.relative = Shadowed.who
  def self.rooted = ::Shadowed.who
end
p Wrapper.relative
p Wrapper.rooted
