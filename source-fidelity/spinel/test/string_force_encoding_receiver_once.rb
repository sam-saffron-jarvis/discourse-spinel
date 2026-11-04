# `force_encoding` / `encode!` / zero-argument `concat` on a receiver that is
# a CALL: the emit fed the receiver expression to both the mutability check
# and the retag, so a receiver with effects ran twice. campfire's
# `request.body.read.force_encoding("UTF-8")` is the caller -- `read`
# advances a cursor, and the second read (the one retagged and returned) was
# empty, so every bot POST arrived with a blank body.
# (Literals are frozen in spinel, so the strings here are built.)
class Body
  def initialize(text)
    @text = text
    @pos = 0
    @reads = 0
  end

  def read
    @reads += 1
    out = @text[@pos, @text.length - @pos].to_s
    @pos = @text.length
    out
  end

  def rewind
    @pos = 0
  end

  def reads
    @reads
  end
end

b = Body.new(String.new("Hello Bot World!"))
p b.read.force_encoding("UTF-8")
p b.reads
b.rewind
p b.read.force_encoding("ASCII-8BIT").bytesize
p b.reads
b.rewind
p b.read.encode!("UTF-8")
p b.reads
b.rewind
p b.read.concat
p b.reads
