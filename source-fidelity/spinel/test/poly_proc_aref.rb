# Proc#[] IS #call, including when the Proc is boxed in a poly slot. The
# emitter's statically-Integer index paths (sp_poly_arr_get_hash for one
# index, sp_poly_slice for two) dispatched only the array/string/hash kinds,
# so a boxed Proc answered nil instead of calling. The shadowed path (some
# user class defines `[]`, so the call reaches the poly method dispatch) is
# covered by poly_call_user_defined_call.rb; this file keeps the unshadowed
# fast paths under test. No class here defines `[]`, so the fast paths are
# the ones exercised.
#
# The snapshot is generated with reference Ruby.

slot = [proc { |x| "p:#{x}" }, 1]
puts slot[0][2]

slot2 = [proc { |a, b| "q:#{a},#{b}" }, 1]
puts slot2[0][3, 4]

# a curried Proc read out of a container already took this path; keep it
# locked so the new plain-Proc arm does not displace it.
add = proc { |a, b| a + b }.curry
cslot = [add, 1]
puts cslot[0][5][6]
