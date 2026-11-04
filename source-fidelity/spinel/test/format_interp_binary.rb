# format / sprintf / String#% and string interpolation sized their operand
# with strlen, so a String with an embedded NUL was cut at the first one --
# and a width then padded the truncation out to the right LENGTH with the
# wrong contents. The byte length is the string's own (sp_str_byte_len, which
# answers strlen for a foreign C string with no header), the same test the
# binary-safe write and puts operands make.
s = "ab\x00cd"
p format("%s", s).bytes
p sprintf("%s", s).bytes
p ("%s" % s).bytes
p ("%s|%s" % [s, s]).bytes
p format("%-8s|", s).bytes          # left-justified, padded to 8
p format("%8s|", s).bytes           # right-justified
p format("%.3s|", s).bytes          # a precision cuts at 3 BYTES
p format("%-8.3s|", s).bytes
p format("%p", s).bytes             # inspect escapes it, so no NUL reaches here
p format("%s-%d-%s", s, 7, s).bytes
p "#{s}".bytes
p "#{s}!".bytes
p "x#{s}y".bytes
p "#{s}#{s}".bytes
p "#{s}#{1}".bytes
p [s].join.bytes                    # join was already right
p ("x" + s).bytes                   # and so was concat
