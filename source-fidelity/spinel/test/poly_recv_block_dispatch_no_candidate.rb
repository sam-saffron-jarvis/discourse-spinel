# The per-class switch for a poly-receiver block call listed only the
# instantiated classes that define the name and closed with NO default arm, so
# a receiver of any other class fell through it and the call silently did
# nothing. CRuby raises NoMethodError. (#3234 is the same hole, found from the
# builtin-array side and patched then only for map!/collect!.)
class Handler
  def handle(x)
    yield "H:#{x}"
  end
end

class Bystander
  def label
    "b"
  end
end

items = [Handler.new, Bystander.new]
items.each do |o|
  r = (o.handle(1) { |v| puts v } ; "returned") rescue $!.class
  p r
end
