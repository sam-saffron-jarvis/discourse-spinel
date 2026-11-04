# A rescued exception's #backtrace. sp_raise_cls has captured the frames since
# #3974, but only the uncaught-drain formatter read them: a RESCUED exception
# answered an empty array, so a program that logs e.backtrace saw its own
# message and nothing about where it came from (#4310).
#
# Driven by `make backtrace-test`, which builds this with --debug (the frame
# substrate is a debug build's; a release build has no symbols and keeps the
# empty array).
class Feeder
  def feed(x)
    inner(x)
  end
  def inner(x)
    raise ArgumentError, "bad #{x}" if x < 0
    x * 2
  end
end

class Driver
  def run(f, x)
    f.feed(x)
  end
end

begin
  Driver.new.run(Feeder.new, -1)
rescue => e
  puts "#{e.class}: #{e.message}"
  e.backtrace.each { |l| puts "  #{l}" }
end
