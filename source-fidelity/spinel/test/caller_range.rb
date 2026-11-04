# Kernel#caller accepts an integer Range literal as a window.
# The Range is rewritten to the (start, len) form: caller(lo..hi) becomes
# sp_caller(lo, 1, hi - lo + 1) and caller(lo...hi) becomes
# sp_caller(lo, 1, hi - lo). Frame *content* is only populated in --debug
# builds, so we verify the window by checking that the length never exceeds
# the requested count, and that the dispatch shape is an Array.

frames = caller(0..3)
puts frames.is_a?(Array)
puts frames.length <= 4

frames = caller(0...3)
puts frames.is_a?(Array)
puts frames.length <= 3

# Regression: integer-typed endpoint expressions must be evaluated
# exactly once and in source order. The codegen previously emitted
# the left endpoint twice (once for start, once for the subtraction),
# which double-evaluated side effects and let C reorder the calls.
log = []
def lo(log)
  log << :lo
  0
end
def hi(log)
  log << :hi
  3
end
caller(lo(log)..hi(log))
puts(log == [:lo, :hi])
