# ARGF answers a line as a whole, however long: it ends at its newline or
# at the end of the input. The stdin sidecar holds a short line, lines of
# 9000 and 16384 bytes (not counting their newlines), another short line,
# and a last line without a newline. On da7617b5 each long line came back
# in 8191-byte pieces.
p ARGF.gets.size
long = ARGF.gets
p [long.size, long[0], long[-1]]
rest = ARGF.readlines
p rest.map(&:size)
p rest.last
