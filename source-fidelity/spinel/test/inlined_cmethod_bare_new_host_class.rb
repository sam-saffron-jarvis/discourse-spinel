# A class method that does `yield new`, called with a block from an INSTANCE
# method of a different class.
#
# The class method is inlined into the caller, and its bare `new` asks the
# emitting class -- which the inliner had left at the HOST method's. So
# `Http.start { |h| ... }` from `Fetch#go` built a Fetch. clang refused on the
# pointer type here; two classes with compatible layouts would have got the
# wrong object with nothing said (#4430).
#
# The instance-receiver branch of the inliner has always set the emitting
# class to the receiver's. The class-method branch set only the method, so
# the host leaked in. Called from the top level there is no host, which is why
# that spelling always worked and is kept below as the control.
class Http
  def self.start
    yield new
  end

  def self.start_self
    yield self.new
  end

  def name = "http"
end

class Fetch
  def go
    Http.start { |h| h.name }
  end

  def go_self
    Http.start_self { |h| h.name }
  end

  # the caller has its own `name`, which must not be what the block sees
  def name = "fetch"
end

puts Fetch.new.go
puts Fetch.new.go_self

# from the top level: no host method, never broken
puts(Http.start { |h| h.name })
