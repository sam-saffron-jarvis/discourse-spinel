# A package's C function bound as :bool returns sp_bool (_Bool, one byte). The
# generated TU prototyped it as int, so the caller read a whole register where
# the callee had written only its low byte: gcc happened to zero the rest,
# ubuntu clang did not, and a fresh StringIO answered closed? as true.
require "stringio"
require "strscan"

s = StringIO.new("hi")
p [s.closed?, s.eof?, s.isatty, s.sync]
s.close
p s.closed?

sc = StringScanner.new("abc")
p [sc.eos?, sc.matched?, sc.rest?]
sc.scan(/a/)
p [sc.eos?, sc.matched?, sc.rest?]
sc.scan(/bc/)
p [sc.eos?, sc.matched?, sc.rest?]
