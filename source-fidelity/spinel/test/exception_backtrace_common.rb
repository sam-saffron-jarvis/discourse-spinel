# An exception subclass whose first ivar is NOT the backtrace:
# the common case for an exception carrying an attribute. The
# #backtrace read must return Array (the captured call stack),
# not the boxed 42 attribute misinterpreted as an sp_StrArray *.
class MyErr < StandardError
  def initialize(msg, code)
    super(msg)
    @code = code
  end
  attr_reader :code
end

begin
  raise MyErr.new("bad", 42)
rescue => e
  raise "wrong backtrace class: #{e.backtrace.class}" unless e.backtrace.is_a?(Array)
  raise "wrong code: #{e.code}" unless e.code == 42
end

# Same shape but with #set_backtrace: the stored backtrace must
# survive and the attribute must not be clobbered.
begin
  e = MyErr.new("bad", 42)
  e.set_backtrace(["frame1", "frame2"])
  bt = e.backtrace
  raise "wrong stored backtrace" unless bt.is_a?(Array) && bt.length == 2
  raise "stored[0] wrong" unless bt[0] == "frame1"
  raise "code clobbered" unless e.code == 42
end

puts "ok"
