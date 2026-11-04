# A block passed to a class method of a class nested in a MODULE.
#
# The block's parameters are typed from what the method yields, and the lookup
# that finds the method accepted only a bare `ConstantReadNode` receiver. A
# constant PATH -- `N::Conn.open` -- named a class just as well and was not
# read, so the method was never found, and the parameter fell through to the
# poly widening a few lines below.
#
# That alone is only a pessimisation: `c` is boxed, and the call inside the
# block goes through a class switch instead of a direct call. It becomes a
# failure when the caller's OWN class defines a method of the same name. The
# switch then opens an arm for the caller too, and inlining a yielding method
# into itself never terminates -- which surfaced as
# "a method that uses its block ... calls itself recursively", three steps
# downstream of the missing lookup (#4416).
#
# So the test needs all three: the module, the class method that yields, and
# `Fetcher#req` sharing a name with `N::Conn#req`. Remove any one and the
# program compiled before this fix.
module N
  class Conn
    def self.open(x)
      c = Conn.new
      begin
        yield c
      ensure
        c.finish
      end
    end

    def req(y)
      r = "resp #{y}"
      yield r if block_given?
      r
    end

    def finish
      @open = false
    end
  end
end

class Fetcher
  def fetch(u)
    req(u) do |resp|
      return "got #{resp}"
    end
  end

  # Same name as N::Conn#req. Inside the block below, `c.req` must resolve on
  # `c` -- an N::Conn -- and not on self.
  def req(u)
    3.times do
      N::Conn.open(u) do |c|
        c.req(u) do |resp|
          yield resp
        end
      end
    end
    "never"
  end
end

puts Fetcher.new.fetch("x")
puts "done"
