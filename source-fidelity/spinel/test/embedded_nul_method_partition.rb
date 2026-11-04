# Which String methods are byte-exact over an embedded NUL and which stop at
# it (#4527): the docs listed twelve as NUL-stopping that had become
# byte-exact and missed the suffix family (end_with?, delete_suffix, chomp,
# each_line(chomp:)), which measured with strlen, and the NUL pad, which
# decoded to nothing and padded nothing. This file is the list; the docs
# section "Embedded NUL bytes" points at it.
# Interpolation and % formatting used to stop at the NUL and were pinned here
# at spinel's answer; they are byte-exact now (#4632), so every line in this
# file is CRuby's.
s = "a\x00bc"
p s.length
p s.end_with?("c")
p s.end_with?("\x00bc")
p s.delete_suffix("c").bytes
p s.delete_suffix("bc").bytes
p s.chomp("c").bytes
p s.chomp.bytes
p "a\x00b\n".chomp.bytes
p "ab\x00".end_with?("b")
p "ab\x00".end_with?("\x00")
p "ab".ljust(6, "\x00").length
p "ab".ljust(6, "\x00").bytes
p "ab".rjust(6, "\x00").bytes
p "ab".center(4, "\x00").bytes
p "ab".ljust(6, "-").length
p "x\x00y\nz\x00".each_line(chomp: true).map(&:bytes)
p "x\x00y\r\nz".each_line(chomp: true).map(&:bytes)
p s.index("c")
p s.start_with?("a")
p s.reverse.bytes
p s.upcase.bytes
p s.strip.bytes
p s.include?("\x00b")
p s.split("\x00").map(&:bytes)
p s.sub("b", "B").bytes
p s.tr("c", "C").bytes
p s.succ.bytes
p("%s!" % s)      # byte-exact since #4632
p "#{s}!".bytes   # ...and so is interpolation
begin
  "ab".ljust(6, "")
rescue ArgumentError => e
  p e.message
end

p s.inspect
p s.upcase.bytes
p s.gsub("b","B").bytes
p s.delete("b").bytes
p s.squeeze.bytes
p s.split("b").map(&:bytes)
p s.tr("a","A").bytes
p s.strip.bytes
p s.index("c")
p s.include?("c")
p s.start_with?("a\x00")
p s.reverse.bytes
p s.succ.bytes
p s.rindex("a")
p s.center(8, "*").bytes
p (s + "d").bytes
p s.byteslice(1, 2).bytes
p s.unpack("C*")
p s.sum
p s.hash == "a\x00bc".hash
p s.each_char.to_a.map(&:bytes)
p s.chars.map(&:bytes)
p s.count("a-c")
p s.scan(/./).map(&:bytes)
p s =~ /c/
p s.encoding
p s.downcase.bytes
p s.capitalize.bytes
p s.swapcase.bytes
p s.lstrip.bytes
p s.rstrip.bytes
p s.chop.bytes
p s.chr.bytes
p s.ord
p s.slice(1..).bytes
p s.partition("b").map(&:bytes)
p s.ljust(6).bytes
p s * 2
p s.freeze.frozen?
