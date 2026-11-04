# Declaring a method takes the BUILTIN of that name away from a boxed receiver.
# `Bucket#partition` below is never instantiated, so nothing can ever call it --
# and yet a valid `String#partition` on a poly receiver compiled to a dispatch
# with no arms at all, a switch whose only branch raises NoMethodError naming
# String, for a method String has (#4413).
#
# The name-collision test now asks the same question the by-reference name
# group asks (#4390): can a call ever ARRIVE at an instance method of this
# class? A class nothing instantiates, and that no instantiated class inherits
# from or includes, cannot own a name.
#
# `split`, `upcase` and `strip` are here as the controls the reporter used:
# each has its own arm ahead of that test, which is why they survived the same
# shadow and made this identifiable.
#
# The second half is an INSTANTIATED class of the same name. Reachability
# cannot help there -- the user method really is callable -- so the dispatch
# itself gets a String pre-arm, the way `include?`, `delete` and the multi-set
# forms already have one. Both receivers then answer their own method.
class Bucket
  def partition(&blk); [[], []]; end
  def rpartition(&blk); [[], []]; end
  def split(n); []; end
  def upcase; ""; end
  def strip; ""; end
end

h = { "p" => "x?y?z", "n" => 1 }

a, sep, b = h["p"].partition("?")
puts "partition #{a}|#{sep}|#{b}"
a, sep, b = h["p"].rpartition("?")
puts "rpartition #{a}|#{sep}|#{b}"
puts "split #{h["p"].split("?").inspect}"
puts "upcase #{h["p"].upcase}"
puts "strip #{h["p"].strip}"

# --- the instantiated half: the user method is genuinely callable ---

class Bin
  def partition(&blk); [[1], [2]]; end
  def rpartition(&blk); [[3], [4]]; end
end

bin = Bin.new
puts "user partition #{bin.partition { |x| x }.inspect}"
puts "user rpartition #{bin.rpartition { |x| x }.inspect}"
a, sep, b = h["p"].partition("?")
puts "string beside it #{a}|#{sep}|#{b}"
a, sep, b = h["p"].rpartition("?")
puts "string beside it r #{a}|#{sep}|#{b}"
