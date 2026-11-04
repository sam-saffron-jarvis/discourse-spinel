require "stringio"

# putc: String writes the first byte; Integer is the codepoint.
io = StringIO.new
io.putc "A"
io.putc 66
io.putc "CD"
puts io.string

# fsync is a no-op returning 0.
io2 = StringIO.new
puts io2.fsync

# StringIO used inside a rescue (setjmp) scope -- exercises the
# volatile-qualifier cast.
def via_rescue
  s = StringIO.new
  s.write("in-")
  s.write("rescue")
  s.string
rescue => e
  "err"
end
puts via_rescue
