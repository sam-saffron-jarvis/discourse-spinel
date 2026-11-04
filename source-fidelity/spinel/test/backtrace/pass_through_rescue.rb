# An exception passing through a rescue that does not match it keeps the
# frames below that rescue. The pass-through raises it again from the
# landing, and snapshotting the stack there cut the backtrace to the
# rescuing method and up, so a debug build's log never named the statement
# that raised (#5084).
#
# Driven by `make backtrace-test` (a --debug build).
class Chain
  def inner(x)
    [1] & x
  end

  def mid(x)
    inner(x)
  end

  def outer(x)
    begin
      mid(x)
    rescue ArgumentError
      nil
    end
  end

  def top(x)
    outer(x)
  rescue => e
    puts e.class
    e.backtrace.each { |l| puts "  #{l}" }
  end
end

Chain.new.top(Object.new)
