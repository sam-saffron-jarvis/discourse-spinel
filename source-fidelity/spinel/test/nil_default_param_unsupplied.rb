# A `= nil` default no call site ever supplies a value for is the whole
# type of the parameter, and the post-fixpoint backstop made it poly (a
# boxed nil) only after the fixpoint had built the body's joins on the
# dropped unknown: `spinel || ENV[...] || "spinel"` typed String, the
# literal holding the ivar Array[String] and `run`'s parameter with it,
# then the ivar re-derived untyped and the C had an sp_PolyArray * meeting
# an sp_StrArray * (a gcc error, silent under clang). The parameter is poly
# from the first round now, so the dependents derive on it (#4583, rubys).
class Runner
  def initialize(spinel = nil)
    @spinel = spinel || ENV["SPINEL_X"] || "spinel"
  end
  def run(argv) = argv.length
  def version = run([@spinel, "--version"])
end
puts Runner.new.version
