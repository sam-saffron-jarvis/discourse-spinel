# --warn-widen's why when a rule, not a value, widened the slot: the rule's
# own words end the chain -- a `= nil` default no call site types, an empty
# literal default, a splat, a parameter no call site binds -- and a chain
# that reaches a read of such a parameter ends the same way.
def opt(a, b = nil) = b.nil? ? a : b
def bag(h = {}) = h
def rest(*xs) = xs.length
def lonely(q) = q
def uses(h = {}) = h.length
puts opt(1), bag.length, rest(1, 2), uses
