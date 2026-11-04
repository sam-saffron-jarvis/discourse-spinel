# A NUL byte inside a line read through ARGF neither ends the line nor
# drops what follows it, also past the first 8 KB of a long line (#4927)
while (l = ARGF.gets)
  p [l.size, l.bytes.count(0), l[-3, 3]]
end
