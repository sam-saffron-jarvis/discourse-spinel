# StringIO#close answers nil, like IO#close. The native binding declared an
# :int return, so it handed back the C function's 0.
require "stringio"

s = StringIO.new("hello")
p s.closed?
p s.close
p s.closed?

t = StringIO.new("world")
p t.read
p t.close
