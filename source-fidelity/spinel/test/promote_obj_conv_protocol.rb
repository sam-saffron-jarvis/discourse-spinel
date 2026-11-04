# promote only: a user class's #to_int at the typed argument slots. Promote
# widens an Integer return to poly, and the implicit-conversion protocol
# recognised a conversion method only by `returns exactly Integer` -- so in
# this mode it did not recognise one at all. Two things followed: the direct
# sites emitted the raw object pointer into an sp_int slot and the generated
# C stopped compiling, and the runtime bridge left the class out of its
# switch, so a boxed receiver was told there is no implicit conversion of a
# class that defines one.
class Idx
  def to_int = 1
end

# the direct sites: the argument is filled by the emitter
p 8[Idx.new]
p 8 >> Idx.new
p [10, 20, 30].take(Idx.new)
p [10, 20, 30].first(Idx.new)
p [10, 20, 30].last(Idx.new)
p "abc".getbyte(Idx.new)
p "abcdef"[Idx.new]
p Time.at(Idx.new).to_i

# the runtime bridge: `<<` promotes to the boxed helper, which reaches the
# compiled #to_int through the generated switch
p 1 << Idx.new
p 4 << Idx.new

# A class without the method is refused at COMPILE time here (the receiver's
# class is settled, so a missing #to_int can only ever raise), which is the
# existing behaviour and is why no such case appears in this file.

# A class whose conversion answers something else STATICALLY can only ever
# raise, so it is refused at compile time with CRuby's own wording -- where
# the raw object pointer used to reach the scalar slot and stop the C build
# with a message about a generated symbol. The refusal itself cannot be
# exercised from a test that must compile; see the PR for the transcript.
