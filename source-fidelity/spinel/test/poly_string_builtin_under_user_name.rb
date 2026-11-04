# A String reaching the poly method dispatch because a user class happens to
# own the name. openssl's buffering.rb defines `getbyte` and `bytesize` for
# SSLSocket, and `require "openssl"` is unconditional, so on 8b9b3f19 every
# `str.getbyte(i)` on a run-time-typed receiver in such a program raised
# "undefined method 'getbyte' for an instance of String". Three dozen more
# names had the same shape: the dispatch's switch carries an arm per user
# class and none for a String.
#
# Each line below reads a String out of a poly-valued Hash, so the receiver
# carries its type only at run time, and calls a name the class above owns.
# The last block is the other half of the rule: the user object still takes
# its own method.
class Sock
  def getbyte(*a) = :sock
  def bytesize(*a) = :sock
  def lstrip(*a) = :sock
  def rstrip(*a) = :sock
  def to_sym(*a) = :sock
  def start_with?(*a) = :sock
  def end_with?(*a) = :sock
  def sub(*a) = :sock
  def gsub(*a) = :sock
  def tr(*a) = :sock
  def center(*a) = :sock
  def ljust(*a) = :sock
  def rjust(*a) = :sock
  def byteslice(*a) = :sock
  def scan(*a) = :sock
  def match(*a) = :sock
  def match?(*a) = :sock
  def unpack1(*a) = :sock
  def b(*a) = :sock
  def ascii_only?(*a) = :sock
  def valid_encoding?(*a) = :sock
  def partition(*a) = :sock
  def rpartition(*a) = :sock
end

h = { "s" => "  xyz  ", "n" => 3 }
k = h["s"]

p k.getbyte(2)
p k.bytesize
p k.lstrip
p k.rstrip
p k.to_sym
p k.start_with?(" ")
p k.end_with?(" ")
p k.sub("x", "q")
p k.gsub("x", "q")
p k.tr("x", "q")
p k.center(11, "-")
p k.ljust(9, "-")
p k.rjust(9, "-")
p k.byteslice(2, 3)
p k.scan("x")
p k.match("y")
p k.match?("y")
p k.unpack1("C")
p k.b
p k.ascii_only?
p k.valid_encoding?
p k.partition("y")
p k.rpartition("y")

s = Sock.new
p s.getbyte(2)
p s.bytesize
p s.sub("x", "q")
p s.match?("y")
