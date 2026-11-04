# A reopened String method whose name the runtime already uses for a function
# of its own: sp_String is the shared-mutable String's type, so `class String;
# def length` emitted an sp_String_length(const char *) beside the runtime's
# sp_String_length(sp_String *) and the program did not compile at all --
# "conflicting types for 'sp_String_length'" -- for length, dup, freeze,
# insert, prepend and replace alike. The reopened method takes an `_oc` stem
# where that happens; a name with no such clash (upcase) is unchanged, and the
# builtin still answers a name the reopen does not define.
class String
  def length = -1
  def dup = "DUP"
  def freeze = "FROZEN"
  def insert(i, s) = "INS"
  def prepend(s) = "PRE"
  def replace(s) = "REP"
  def upcase = "UP"
end
s = "ab"
p s.length
p s.dup
p s.freeze
p s.insert(0, "x")
p s.prepend("y")
p s.replace("z")
p s.upcase
p s.size
p s.downcase
