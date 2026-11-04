# Array[String]#include? / #index with an argument the static type cannot
# pin to String (a `String | nil` reader, a value out of a poly container):
# an equality scan answers false / nil for a nil or a non-String, where the
# argument used to be unboxed as a String and raised TypeError (#4458).
class Resp
  def initialize(ct); @ct = ct; end
  def content_type
    @ct
  end
end
def textual?(r)
  %w[text/html text/plain].include?(r.content_type)
end
def where(r)
  %w[text/html text/plain].index(r.content_type)
end
p textual?(Resp.new("text/html"))
p textual?(Resp.new(nil))
p textual?(Resp.new(42))
p where(Resp.new("text/plain"))
p where(Resp.new(nil))
vals = ["text/plain", nil, 7, :sym, "nope"]
kinds = %w[text/html text/plain]
vals.each { |v| p kinds.include?(v) }
p kinds.member?(nil)
