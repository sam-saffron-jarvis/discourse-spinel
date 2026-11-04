# Base exception: set + read backtrace.
e1 = StandardError.new("base boom")
e1.set_backtrace(["base:1", "base:2", "base:3"])
bt1 = e1.backtrace
raise "base count wrong" unless bt1.length == 3
raise "base[0] wrong" unless bt1[0] == "base:1"
raise "base[2] wrong" unless bt1[2] == "base:3"

# User exception subclass with its own #set_backtrace/#backtrace
# (storing in @__bt) and a separate @tag ivar. The shared accessor
# contract says the user method and the spinel builtin must not
# clobber each other's storage. Here the user method wins (the
# chain check in the codegen arm stands down for any class that
# defines its own), so @__bt holds the backtrace and @tag survives.
class TaggedError < StandardError
  def initialize(msg, tag)
    super(msg)
    @tag = tag
  end
  def set_backtrace(bt)
    @__bt = bt
  end
  def backtrace
    @__bt
  end
  attr_reader :tag
end

e2 = TaggedError.new("sub boom", "tag42")
e2.set_backtrace(["sub:1", "sub:2"])
bt2 = e2.backtrace
raise "sub count wrong" unless bt2.length == 2
raise "sub[0] wrong" unless bt2[0] == "sub:1"
raise "sub[1] wrong" unless bt2[1] == "sub:2"
raise "tag clobbered" unless e2.tag == "tag42"

# Re-raise a user exception subclass and read the backtrace from
# a typed rescue (the analyze pass keeps the concrete class, so
# the user #backtrace method dispatches, not the builtin).
begin
  raise e2
rescue TaggedError => caught
  cbt = caught.backtrace
  raise "rescue count wrong" unless cbt.length == 2
  raise "rescue[0] wrong" unless cbt[0] == "sub:1"
  raise "caught tag wrong" unless caught.tag == "tag42"
end

puts "ok"
