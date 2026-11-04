# `blk.call` in a method that declares `&blk` and never yields.
#
# A block parameter's call is typed from the call site's block, the way a
# yield is. A method reached through `extend` is called with a proc BUILT at
# the call site rather than spliced into it, and it has no yield for the
# machinery to follow either, so no call site could say what the block
# answers and the type stayed unknown.
#
# Unknown is not an answer, and the way it degrades is silent: emit_call's
# nil-degrade placeholders fold `.to_s` on an unresolved receiver to the
# empty string and `.inspect` to "[]", so `blk.call.to_s` printed "" for a
# block plainly returning "ran". The value is decided at run time, which is
# poly.
module DSL
  def run(&blk)
    if blk
      blk.call
    else
      "none"
    end
  end

  def shout(&blk)
    blk ? blk.call.to_s.upcase : "NONE"
  end

  def show(&blk)
    blk ? blk.call.inspect : "none"
  end
end
extend DSL

p run { "ran" }
p run
p shout { "ran" }
p shout
p show { "ran" }
p show { 7 }
p show { [1, 2] }

# a block answering different types at different sites still works: the
# value is boxed, so each site carries its own
p run { 7 }
p run { [1, 2] }
