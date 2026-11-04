# A program that assigns its own constant named TrueClass (here Integer):
# a boolean no longer matches that name by its value, while FalseClass
# still does. On ec604b80 the first line already prints what the .expected
# holds; the second prints the no-match answer.
$VERBOSE = nil   # reassigning TrueClass warns
TrueClass = Integer

t = 3 > 2
f = 3 < 2
puts(case t; in TrueClass then "true class"; else "other"; end)
puts(case f; in FalseClass then "false class"; else "other"; end)
