# The shape rubys/spinel-ide's LSP has: the never-supplied `= nil` parameter
# feeds an ivar, the ivar a literal, the literal a parameter -- and the
# method with the second literal (`version`) is never called, so `run`'s
# parameter binds only from `analyze`'s. The optimistic re-narrow loop
# re-clears the poly parameter and the ivar, re-binds `run` while the ivar
# is still unknown, and the ivar then re-derives untyped after `run` has
# settled on Array[String]: the seed runs at the top of that loop too, and
# the program also defines `send`, which the supply scan must read as an
# ordinary method rather than Kernel#send (#4583, rubys).
class R
  def initialize(spinel = nil)
    @spinel = spinel || ENV["X"] || "s"
    @tmpdir = "/tmp"
    @seq = 0
  end
  def run(argv)
    errfile = "#{@tmpdir}/q-#{@seq += 1}.err"
    cmd = argv.map { |a| shell_quote(a) }.join(" ") + " 2>" + shell_quote(errfile)
    [cmd, "", 1]
  end
  def shell_quote(s)
    "'" + s.gsub("'", "'\\\\''") + "'"
  end
  def version
    out, _err, _rc = run([@spinel, "--version"])
    out.strip
  end
  def analyze(path, text = nil)
    stamp = "#{path}.x"
    types_out, types_err, types_rc = run([@spinel, path, "--emit-types", "-o", "#{stamp}.json", "-S"])
    types_out
  end
end
r = R.new

puts r.analyze("x.rb").length
class Srv
  def initialize(runner) = @runner = runner
  def send(obj) = obj.to_s.length
  def go = send(@runner.analyze("y.rb"))
end
puts Srv.new(R.new).go
